# frozen_string_literal: true

module Routing
  module Concurrency
    class Clock
      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def wall
        Time.now
      end

      def dispatch_time(_operation)
        monotonic
      end

      def real_delay(seconds)
        seconds
      end

      def timeout_time(operation, context)
        operation.created_at.nil? ? wall : operation.created_at + context.total_latency
      end
    end
  end
end
