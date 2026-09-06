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
        @clock = engine.replay&.clock || Clock.new
        @payouts = 0
        @statuses = 0
        @feeding = true
        @lock = Mutex.new
      end

      def call
        failure = Async do |task|
          run(task)
          nil
        rescue Exception => e # rubocop:disable Lint/RescueException
          e
        end.wait
        raise failure unless failure.nil?

        decisions = @engine.operations.map { |operation| @engine.decisions_by_id.fetch(operation.id) }
        unresolved = decisions.reject(&:final?)
        return decisions if unresolved.empty?

        raise InvalidInputError,
              "operations remain reconciliation_pending: #{unresolved.map(&:operation_id).join(', ')}"
      end

      private

      def run(task)
        setup(task)
        feeder = task.async { |child| feed_operations(child) }
        settlement_task = task.async { settlement_loop }
        status_task = task.async { status_loop(task) }
        begin
          admission_loop(task)
          feeder.wait
          settlement_task.wait
          status_task.wait
        rescue Exception # rubocop:disable Lint/RescueException
          @progress.stop
          settlement_task.stop
          status_task.stop
          raise
        ensure
          feeder.stop
          @slots.shutdown
          @status_pool.shutdown
          @persist.shutdown
        end
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

      def enqueue_operation(operation)
        @engine.track_operation!(operation)
        @inbound.push(WorkItem.new(operation, RouteContext.new))
      end

      def admission_loop(task)
        loop do
          checkpoint = @progress.version
          item = @inbound.shift
          if item
            parked = @admission.admit(item)
            wait_for_capacity(task, after: checkpoint) if parked == :parked
            next
          end
          break if done?

          wait_for_progress(task, after: checkpoint, key: :admission)
        end
      end

      def settlement_loop
        loop do
          checkpoint = @progress.version
          event = @events.shift
          if event.nil?
            break if done?

            @progress.wait(key: :settlement, after: checkpoint)
            next
          end

          @settlement.handle(event)
          @progress.signal
        end
      end

      def status_loop(task)
        loop do
          checkpoint = @progress.version
          break if done?

          now = @clock.wall
          available = @status_pool.available_slots
          if available.zero?
            wait_for_progress(task, after: checkpoint, key: :status)
            next
          end
          due = @engine.status_checker.take_due(now, limit: available)
          if due.empty?
            wait_for_status(task, now, after: checkpoint)
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

      def wait_for_status(task, now, after:)
        nxt = @engine.status_checker.next_check_at
        delay = nxt.nil? ? nil : [nxt - now, 0].max
        wait_for_progress(task, delay, after: after, key: :status)
      end

      def feed_operations(task)
        if @engine.replay
          @engine.replay.feed(task) { |operation| enqueue_operation(operation) }
        else
          @engine.operations.each { |operation| enqueue_operation(operation) }
        end
      ensure
        @feeding = false
        @progress.signal
      end

      def wait_for_capacity(task, after:)
        task.sleep(0)
        now = @clock.monotonic
        delay = @engine.providers.filter_map { |provider| provider.intensity_retry_delay(now) }.min
        wait_for_progress(task, delay, after: after, key: :admission)
      end

      def wait_for_progress(task, delay = nil, after:, key:)
        return if @progress.stopped?
        return @progress.wait(key: key, after: after) if delay.nil?

        if delay <= 0
          task.sleep(0)
        else
          task.with_timeout(@clock.real_delay(delay)) { @progress.wait(key: key, after: after) }
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
          !@feeding && @inbound.empty? && @events.empty? && @payouts.zero? && @statuses.zero? &&
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
