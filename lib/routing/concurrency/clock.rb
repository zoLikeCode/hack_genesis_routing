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

      def dispatch_time(operation)
        operation.created_at || wall
      end
    end
  end
end
