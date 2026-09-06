# frozen_string_literal: true

require "async"

module Routing
  module Concurrency
    class Supervisor
      def self.call(engine)
        new(engine).call
      end

      def initialize(engine)
        Routing.assert(engine.is_a?(Engine), "supervisor requires Engine")
        @engine = engine
        @clock = Clock.new
        @payouts = 0
        @statuses = 0
        @lock = Mutex.new
      end

      def call
        Async { |task| run(task) }
        @engine.operations.map { |operation| @engine.decisions_by_id.fetch(operation.id) }
      end

      private

      def run(task)
        setup(task)
        enqueue_operations
        settlement_task = task.async { settlement_loop }
        status_task = task.async { status_loop(task) }
        admission_loop(task)
        @progress.stop
        @events.push(:stop)
        settlement_task.wait
        status_task.wait
        @slots.shutdown
        @status_pool.shutdown
        @persist.shutdown
      end

      def setup(task)
        config = @engine.policy.concurrency
        @progress = Progress.new
        @inbound = InboundQueue.new(progress: @progress)
        @events = SettlementQueue.new(progress: @progress)
        build_executors(task, config)
        @persist = PersistQueue.new(
          store: @engine.runtime_store,
          debounce_ms: config.fetch("persist_debounce_ms"),
          event_log: config.fetch("event_log")
        )
        build_coordinators
      end

      def build_executors(task, config)
        executor_class = executor_class_for(config.fetch("executor"))
        @slots = DispatchSlots.new(
          providers: @engine.providers,
          policy: @engine.policy,
          executor_class: executor_class,
          reactor_task: task
        )
        @status_pool = executor_class.new(
          limit: config.fetch("status_worker_limit"),
          reactor_task: task
        )
      end

      def build_coordinators
        @admission = AdmissionCoordinator.new(
          engine: @engine, inbound: @inbound, slots: @slots, events: @events,
          progress: @progress, clock: @clock, payouts: method(:adjust_payouts)
        )
        @settlement = SettlementCoordinator.new(
          engine: @engine, inbound: @inbound, persist: @persist, clock: @clock
        )
        @status_worker = StatusWorker.new(checker: @engine.status_checker, events: @events)
      end

      def executor_class_for(name)
        return Execution::FiberPool if name == "fiber_pool"
        return Execution::ThreadPool if name == "thread_pool"

        Routing.assert(false, "unknown executor #{name}")
      end

      def enqueue_operations
        @engine.operations.each do |operation|
          @engine.track_operation!(operation)
          @inbound.push(WorkItem.new(operation, RouteContext.new))
        end
      end

      def admission_loop(task)
        loop do
          item = @inbound.shift
          if item
            parked = @admission.admit(item)
            wait_for_capacity(task) if parked == :parked
            next
          end
          break if done?

          wait_for_progress(task)
        end
      end

      def settlement_loop
        loop do
          event = @events.shift
          if event.nil?
            break if done?

            @progress.wait
            next
          end
          break if event == :stop

          @settlement.handle(event)
          @progress.signal
        end
      end

      def status_loop(task)
        loop do
          break if done?

          now = @clock.wall
          due = @engine.status_checker.take_due(now)
          if due.empty?
            wait_for_status(task, now)
            next
          end

          due.each { |status_task| submit_status(status_task, now) }
        end
      end

      def submit_status(status_task, now)
        adjust_statuses(1)
        @status_pool.submit do
          @status_worker.perform(status_task, now)
        ensure
          adjust_statuses(-1)
          @progress.signal
        end
      end

      def wait_for_status(task, now)
        nxt = @engine.status_checker.next_check_at
        delay = nxt.nil? ? nil : [nxt - now, 0].max
        wait_for_progress(task, delay)
      end

      def wait_for_capacity(task)
        now = @clock.wall
        delay = @engine.providers.filter_map { |provider| provider.intensity_retry_delay(now) }.min
        wait_for_progress(task, delay)
      end

      def wait_for_progress(task, delay = nil)
        return if @progress.stopped?
        return @progress.wait if delay.nil?

        if delay <= 0
          task.sleep(0)
        else
          task.with_timeout(delay) { @progress.wait }
        end
      rescue Async::TimeoutError
        nil
      end

      def done?
        return false unless finished?

        @progress.stop
        true
      end

      def finished?
        @lock.synchronize do
          @inbound.empty? && @events.empty? && @payouts.zero? && @statuses.zero? &&
            !@engine.status_checker.active?
        end
      end

      def adjust_payouts(delta)
        @lock.synchronize { @payouts += delta }
      end

      def adjust_statuses(delta)
        @lock.synchronize { @statuses += delta }
      end
    end
  end
end
