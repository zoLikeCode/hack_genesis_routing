# frozen_string_literal: true

require "async"
require "async/semaphore"

module Routing
  module Execution
    class FiberPool < Executor
      def initialize(limit:, reactor_task: nil)
        super()
        Routing.assert(limit.is_a?(Integer) && limit.positive?, "fiber pool limit must be a positive integer")
        @limit = limit
        @parent = reactor_task
        @in_flight = 0
        @tasks = []
        @semaphore = Async::Semaphore.new(limit, parent: reactor_task)
      end

      def try_submit # rubocop:disable Naming/PredicateMethod
        available_slots.positive?
      end

      def available_slots
        @limit - @in_flight
      end

      def submit
        Routing.assert(block_given?, "fiber pool submit requires a block")
        Routing.assert(try_submit, "fiber pool has no free slot")
        @in_flight += 1
        @tasks << @semaphore.async(parent: parent_task) do
          yield
        ensure
          @in_flight -= 1
        end
      end

      def shutdown
        @tasks.each(&:wait)
        @tasks.clear
        self
      end

      private

      def parent_task
        @parent || Async::Task.current
      end
    end
  end
end
