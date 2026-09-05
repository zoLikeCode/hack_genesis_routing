# frozen_string_literal: true

module Routing
  class Engine
    module Recording
      def record_failed_try(operation, _provider, reservation)
        return unless reservation.active?

        @state.record_outcome!(
          reservation: reservation, operation: operation, status: "rejected", latency_sec: 0
        )
      end
    end
  end
end
