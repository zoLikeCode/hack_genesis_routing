# frozen_string_literal: true

module Routing
  module Concurrency
    class SettlementQueue
      def initialize(progress:)
        @items = []
        @mutex = Mutex.new
        @progress = progress
      end

      def push(event)
        @mutex.synchronize { @items << event }
        @progress.signal
        self
      end

      def shift
        @mutex.synchronize { @items.shift }
      end

      def empty?
        @mutex.synchronize { @items.empty? }
      end
    end
  end
end
