# frozen_string_literal: true

module Routing
  class Settlement
    def initialize(state:, policy:, status_check_runner:, persist:)
      Routing.assert(state.is_a?(RuntimeState), "settlement requires RuntimeState")
      Routing.assert(policy.is_a?(Policy), "settlement requires Policy")
      Routing.assert(status_check_runner.is_a?(StatusCheckRunner), "settlement requires StatusCheckRunner")
      Routing.assert(persist.respond_to?(:call), "settlement persist must be callable")
      @state = state
      @policy = policy
      @status_check_runner = status_check_runner
      @persist = persist
    end

    def apply_payout(operation:, selection:, context:, outcome:, reservation:, timeout_at:) # rubocop:disable Metrics/ParameterLists
      result = outcome.fetch(:result)
      @state.record_outcome!(
        reservation: reservation, operation: operation, status: result,
        latency_sec: outcome.fetch(:latency_sec)
      )
      return complete(operation, selection, context, outcome, final: true) if result == "approved"

      if result == "expired"
        @status_check_runner.schedule(reservation, timed_out_at: timeout_at)
        return complete(operation, selection, context, outcome, final: false)
      end

      return complete(operation, selection, context, outcome, final: true) if selection.fallback?

      context.add_attempt!(skip_attempt(selection.provider.name, simulation_reason(result), nil))
      context.clear_temporarily_excluded!
      nil
    end

    def apply_failure(operation:, selection:, context:, reservation:, error:, timeout_at:) # rubocop:disable Metrics/ParameterLists
      return drop_unsent(selection, context, reservation) if error.definite_miss?

      Routing.assert(error.ambiguous?, "unhandled adapter error kind #{error.kind}")
      apply_payout(
        operation: operation,
        selection: selection,
        context: context,
        outcome: { result: "expired", latency_sec: 0 },
        reservation: reservation,
        timeout_at: timeout_at
      )
    end

    def complete(operation, selection, context, outcome, final:)
      record_considered_skips!(selection, context)
      context.add_attempt!(selected_attempt(selection, outcome))
      Decision.new(
        operation_id: operation.id,
        selected_provider: selection.provider.name,
        attempts: context.attempts,
        simulated_result: outcome.fetch(:result),
        latency_sec: context.total_latency,
        final: final
      )
    end

    private

    def drop_unsent(selection, context, reservation)
      @state.drop_reservation!(reservation)
      context.add_attempt!(
        skip_attempt(selection.provider.name, "adapter_not_sent", "payout was not dispatched")
      )
      context.exclude_temporarily!(selection.provider.name)
      nil
    end

    def record_considered_skips!(selection, context)
      return if selection.fallback?

      winner = selection.provider
      winner_score = selection.ranking.scores.fetch(winner.name)
      selection.ranking.ordered.each do |provider|
        next if provider.name == winner.name

        score = selection.ranking.scores.fetch(provider.name)
        context.add_attempt!(
          skip_attempt(
            provider.name,
            SoftGoals::Reasons::LOWER_SOFT_SCORE,
            "total_score=#{score.total.round(4)} vs #{winner.name} #{winner_score.total.round(4)}"
          )
        )
      end
    end

    def selected_attempt(selection, outcome)
      HardConstraints::Attempt.new(
        provider: selection.provider.name,
        decision: "selected",
        reason: selected_reason(selection),
        details: DecisionExplainer.details(
          selection: selection,
          policy: @policy,
          result: outcome.fetch(:result)
        )
      )
    end

    def selected_reason(selection)
      return Engine::FALLBACK_SELECTED if selection.fallback?

      selection.ranking.scores.fetch(selection.provider.name).reason
    end

    def simulation_reason(result)
      return Simulator::REJECTED if result == "rejected"
      return Simulator::EXPIRED if result == "expired"

      Routing.assert(false, "unexpected simulation result #{result}")
    end

    def skip_attempt(name, reason, details)
      HardConstraints::Attempt.new(provider: name, decision: "skipped", reason: reason, details: details)
    end
  end
end
