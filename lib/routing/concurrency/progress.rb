# frozen_string_literal: true

require "async"

module Routing
  module Concurrency
    class Progress
      def initialize
        @notification = Async::Notification.new
        @version = 0
        @stopped = false
      end

      def stopped?
        @stopped
      end

      def signal
        @version += 1
        @notification.signal
        self
      end

      def stop
        @stopped = true
        signal
        self
      end

      def wait
        seen = @version
        @notification.wait while !@stopped && @version == seen
        self
      end
    end
  end
end
