# frozen_string_literal: true

module Routing
  class Admission
    def initialize(state:, policy:, circuit_breaker:)
      Routing.assert(state.is_a?(RuntimeState), "admission requires RuntimeState")
      Routing.assert(policy.is_a?(Policy), "admission requires Policy")
      Routing.assert(circuit_breaker.is_a?(CircuitBreaker), "admission requires CircuitBreaker")
      @state = state
      @policy = policy
      @circuit_breaker = circuit_breaker
    end

    def pick(operation, context)
      Routing.assert(operation.is_a?(Operation), "operation must be Routing::Operation")
      Routing.assert(context.is_a?(RouteContext), "context must be Routing::RouteContext")
      exclude_open_circuits!(context)
      snapshot = @state.snapshot
      selection = Router.call(
        operation: operation,
        providers: snapshot.providers,
        snapshot: snapshot.soft_goals,
        policy: @policy,
        attempted: context.attempted,
        temporarily_excluded: context.temporarily_excluded
      )
      [selection, snapshot]
    end

    def reserve(selection, operation, snapshot)
      @state.try_reserve!(
        selection.provider,
        operation,
        expected_revision: snapshot.revision
      )
    end

    def handle_stale(context)
      context.clear_temporarily_excluded!
      nil
    end

    def handle_ineligible(selection, reserved, context)
      context.add_attempt!(skip_attempt(selection.provider.name, reserved.reason, reserved.details))
      context.exclude_temporarily!(selection.provider.name)
      nil
    end

    private

    def exclude_open_circuits!(context)
      @circuit_breaker.open_provider_names.each do |provider_name|
        next if context.attempted.include?(provider_name)
        next if context.temporarily_excluded.include?(provider_name)

        context.add_attempt!(
          skip_attempt(
            provider_name,
            HardConstraints::Reasons::CIRCUIT_BREAKER_OPEN,
            "unresolved payout threshold reached"
          )
        )
        context.exclude_temporarily!(provider_name)
      end
    end

    def skip_attempt(name, reason, details)
      HardConstraints::Attempt.new(provider: name, decision: "skipped", reason: reason, details: details)
    end
  end
end
