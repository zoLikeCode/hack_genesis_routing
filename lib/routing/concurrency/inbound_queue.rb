# frozen_string_literal: true

module Routing
  module Concurrency
    class InboundQueue
      def initialize(progress:)
        @items = []
        @mutex = Mutex.new
        @progress = progress
      end

      def push(item)
        Routing.assert(item.is_a?(WorkItem), "inbound queue requires WorkItem")
        @mutex.synchronize { @items << item }
        @progress.signal
        self
      end

      def unshift(item)
        Routing.assert(item.is_a?(WorkItem), "inbound queue requires WorkItem")
        @mutex.synchronize { @items.unshift(item) }
        @progress.signal
        self
      end

      def shift
        @mutex.synchronize { @items.shift }
      end

      def empty?
        @mutex.synchronize { @items.empty? }
      end

      def size
        @mutex.synchronize { @items.size }
      end
    end
  end
end
