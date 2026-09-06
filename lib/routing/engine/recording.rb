# frozen_string_literal: true

module Routing
  class Engine
    module Recording
      def simulate_try(provider, operation, reservation)
        ProviderInvoker.call(
          client: @simulator,
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
