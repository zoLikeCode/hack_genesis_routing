# frozen_string_literal: true

module Routing
  module Concurrency
    class SettlementQueue
      def initialize(progress:)
        @items = []
        @progress = progress
      end

      def push(event)
        @items << event
        @progress.signal
        self
      end

      def shift
        @items.shift
      end

      def empty?
        @items.empty?
      end
    end
  end
end
