# frozen_string_literal: true

module Routing
  class Engine
    module Recording
      def record_metric(operation, provider, outcome)
        @state.record_metric!(
          operation: operation,
          provider_name: provider.name,
          status: outcome.fetch(:result),
          latency_sec: outcome.fetch(:latency_sec)
        )
      end

      def record_failed_try(operation, provider, reservation)
        return unless reservation.active?

        @state.reject!(reservation)
        @state.record_metric!(
          operation: operation, provider_name: provider.name, status: "rejected", latency_sec: 0
        )
      end
    end
  end
end
