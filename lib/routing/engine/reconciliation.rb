# frozen_string_literal: true

module Routing
  class Engine
    module Reconciliation
      private

      def run_due_status_checks(operation)
        return if operation.created_at.nil?

        result = @status_check_runner.run_due(now: operation.created_at)
        handle_status_settlements(result)
        persist_runtime! if result.fetch("checked").positive?
      end

      def handle_status_settlements(result)
        result.fetch("settlements", []).each do |settlement|
          reroute_after_status_rejection(settlement) if settlement.fetch("result") == "rejected"
        end
      end

      def reroute_after_status_rejection(settlement)
        operation, previous, provider_name = reconciliation_context(settlement)
        return unless reroutable_reconciliation?(operation, previous, provider_name)

        context = RouteContext.new(
          attempts: reconciled_attempts(previous, provider_name),
          attempted: reserved_provider_names_for(operation),
          total_latency: previous.latency_sec
        )
        @decisions_by_id[operation.id] = route(operation, context: context)
      end

      def reserved_provider_names_for(operation)
        @state.reservations.filter_map do |reservation|
          reservation.provider_name if reservation.operation_id == operation.id
        end
      end

      def reconciliation_context(settlement)
        operation_id = settlement.fetch("operation_id")
        [@operations_by_id[operation_id], @decisions_by_id[operation_id], settlement.fetch("provider")]
      end

      def reroutable_reconciliation?(operation, previous, provider_name)
        return false if operation.nil? || previous.nil? || provider_name == @policy.fallback_provider

        previous.selected_provider == provider_name && previous.simulated_result == "expired"
      end

      def reconciled_attempts(previous, provider_name)
        previous.attempts.map do |attempt|
          next attempt unless attempt.provider == provider_name && attempt.decision == "selected"

          status_rejected_attempt(provider_name)
        end
      end

      def status_rejected_attempt(provider_name)
        HardConstraints::Attempt.new(
          provider: provider_name,
          decision: "skipped",
          reason: STATUS_CHECK_REJECTED,
          details: "terminal status-check rejected payout; reservation released"
        )
      end

      def exclude_open_circuits!(context)
        @circuit_breaker.open_provider_names.each do |provider_name|
          next if context.attempted.include?(provider_name)

          context.add_attempt!(
            skip_attempt(provider_name, CIRCUIT_BREAKER_OPEN, "unresolved payout threshold reached")
          )
          context.mark_attempted!(provider_name)
        end
      end

      def persist_runtime!
        @runtime_store&.save(state: @state, status_checker: @status_checker)
      end
    end
  end
end
