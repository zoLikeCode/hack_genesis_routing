# frozen_string_literal: true

module Routing
  module Concurrency
    class SettlementCoordinator
      def initialize(engine:, inbound:, persist:, clock:)
        @engine = engine
        @inbound = inbound
        @persist = persist
        @clock = clock
      end

      def handle(event)
        case event
        when PayoutEvent
          handle_payout(event)
        when StatusEvent
          handle_status(event.payload)
        else
          Routing.assert(false, "unknown settlement event #{event.inspect}")
        end
        @persist.enqueue(state: @engine.state, status_checker: @engine.status_checker)
      end

      private

      def handle_payout(event)
        context = event.item.context
        timeout_at = timeout_time(event.item.operation, context)
        decision = settle_payout(event, context, timeout_at)
        if decision
          @engine.store_decision!(event.item.operation.id, decision)
        else
          @inbound.push(event.item)
        end
      end

      def settle_payout(event, context, timeout_at)
        if event.outcome.is_a?(AdapterError)
          return @engine.settlement.apply_failure(
            operation: event.item.operation, selection: event.selection, context: context,
            reservation: event.reservation, error: event.outcome, timeout_at: timeout_at
          )
        end

        context.add_latency!(event.outcome.fetch(:latency_sec))
        @engine.settlement.apply_payout(
          operation: event.item.operation, selection: event.selection, context: context,
          outcome: event.outcome, reservation: event.reservation, timeout_at: timeout_at
        )
      end

      def handle_status(payload)
        if payload.fetch("result") == "approved"
          @engine.finalize_status_decision!(payload)
          return
        end

        item = @engine.status_cascade_item(payload)
        if item.nil?
          @engine.finalize_status_decision!(payload)
        else
          @inbound.push(item)
        end
      end

      def timeout_time(operation, context)
        @clock.timeout_time(operation, context)
      end
    end
  end
end
