# frozen_string_literal: true

module Routing
  module Execution
    class ThreadPool < Executor
      def initialize(limit:, reactor_task: nil) # rubocop:disable Lint/UnusedMethodArgument
        super()
        Routing.assert(limit.is_a?(Integer) && limit.positive?, "thread pool limit must be a positive integer")
        @limit = limit
        @in_flight = 0
        @mutex = Mutex.new
        @idle = ConditionVariable.new
        @jobs = Queue.new
        @workers = Array.new(limit) { Thread.new { run_worker } }
      end

      def try_submit # rubocop:disable Naming/PredicateMethod
        available_slots.positive?
      end

      def available_slots
        @mutex.synchronize { @limit - @in_flight }
      end

      def submit(&work)
        Routing.assert(work, "thread pool submit requires a block")
        @mutex.synchronize do
          Routing.assert(@in_flight < @limit, "thread pool has no free slot")
          @in_flight += 1
        end
        @jobs << work
      end

      def shutdown
        @limit.times { @jobs << nil }
        @workers.each(&:join)
        self
      end

      private

      def run_worker
        loop do
          work = @jobs.pop
          break if work.nil?

          begin
            work.call
          ensure
            finish_job
          end
        end
      end

      def finish_job
        @mutex.synchronize do
          @in_flight -= 1
          @idle.signal
        end
      end
    end
  end
end
