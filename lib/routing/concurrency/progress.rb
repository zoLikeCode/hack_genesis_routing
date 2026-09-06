# frozen_string_literal: true

require "async/queue"

module Routing
  module Concurrency
    class Progress
      def initialize
        @queues = {}
        @mutex = Mutex.new
        @version = 0
        @stopped = false
        @waiting = {}
      end

      def stopped?
        @mutex.synchronize { @stopped }
      end

      def version
        @mutex.synchronize { @version }
      end

      def signal
        queues = @mutex.synchronize do
          return self if @stopped

          @version += 1
          @waiting.keys.filter_map { |key| @queues[key] }
        end
        queues.each { |queue| queue.enqueue(true) }
        self
      end

      def stop
        queues = @mutex.synchronize do
          return self if @stopped

          @stopped = true
          @version += 1
          @queues.values
        end
        queues.each(&:close)
        self
      end

      def wait(key:, after: version)
        queue = @mutex.synchronize do
          return self if @stopped || @version != after

          Routing.assert(!@waiting.key?(key), "duplicate progress waiter #{key}")
          @waiting[key] = true
          @queues[key] ||= Async::Queue.new
        end
        loop do
          queue.dequeue
          break if @mutex.synchronize { @stopped || @version != after }
        end
        self
      ensure
        @mutex.synchronize { @waiting.delete(key) } if queue
      end
    end
  end
end
