# frozen_string_literal: true

module Routing
  module Concurrency
    class InboundQueue
      def initialize(progress:)
        @items = []
        @progress = progress
      end

      def push(item)
        Routing.assert(item.is_a?(WorkItem), "inbound queue requires WorkItem")
        @items << item
        @progress.signal
        self
      end

      def unshift(item)
        Routing.assert(item.is_a?(WorkItem), "inbound queue requires WorkItem")
        @items.unshift(item)
        @progress.signal
        self
      end

      def shift
        @items.shift
      end

      def empty?
        @items.empty?
      end

      def size
        @items.size
      end
    end
  end
end
