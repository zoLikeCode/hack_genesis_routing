# frozen_string_literal: true

module Routing
  module Concurrency
    class PayoutWorker
      def initialize(engine:, events:)
        @engine = engine
        @events = events
      end

      def perform(item, selection, reservation)
        outcome = invoke(selection.provider, item.operation, reservation)
        @events.push(PayoutEvent.new(item, selection, reservation, outcome))
      end

      private

      def invoke(provider, operation, reservation)
        ProviderInvoker.call(
          client: @engine.client,
          provider: provider,
          operation: operation,
          reservation: reservation
        )
      rescue Routing::Error
        raise
      rescue StandardError => e
        AdapterError.from(e, reservation: reservation)
      end
    end
  end
end
