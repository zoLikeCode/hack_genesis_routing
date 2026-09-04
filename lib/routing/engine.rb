# frozen_string_literal: true

module Routing
  class Engine
    FALLBACK_SELECTED = "fallback_selected"

    attr_reader :state

    def self.call(operations:, providers:, policy:, simulator: nil, state: nil)
      new(operations, providers, policy, simulator, state: state).call
    end

    def initialize(operations, providers, policy, simulator = nil, state: nil)
      Routing.assert(operations.respond_to?(:each), "operations must be enumerable")
      Routing.assert(providers.is_a?(ProviderPool), "providers must be a ProviderPool")
      Routing.assert(policy.is_a?(Policy), "policy must be Routing::Policy")
      @operations = operations
      @providers = providers
      @policy = policy
      apply_default_requests_per_minute_limit!
      @simulator = simulator || Simulator.new(seed: policy.simulation_seed)
      @state = state || RuntimeState.new(providers)
      Routing.assert(@state.is_a?(RuntimeState), "state must be Routing::RuntimeState")
      Routing.assert(@state.providers.equal?(providers), "runtime state must own the provider pool")
      @processed_ids = {}
      @last_created_at = nil
    end

    def call
      @operations.each_with_object([]) { |operation, decisions| decisions << route_one(operation) }
    end

    def route_one(operation)
      validate_online_operation!(operation)
      decision = route(operation)
      @processed_ids[operation.id] = true
      @last_created_at = operation.created_at unless operation.created_at.nil?
      decision
    end

    private

    def apply_default_requests_per_minute_limit!
      limit = @policy.default_requests_per_minute_limit
      @providers.apply_default_requests_per_minute_limit!(limit) unless limit.nil?
    end

    def route(operation)
      Routing.assert(operation.is_a?(Operation), "operation must be Routing::Operation")
      context = RouteContext.new

      loop do
        decision = route_attempt(operation, context)
        return decision if decision
      end
    end

    def route_attempt(operation, context)
      selection, runtime_snapshot = pick(operation, context.attempted)
      return resolve_unroutable(operation, selection, runtime_snapshot, context) unless selection.routable?

      reserved = reserve(selection, operation, runtime_snapshot)
      return if reserved.stale?

      context.merge_skips!(selection.evaluation.skipped)
      return reservation_failed(selection, reserved, context) unless reserved.reserved?

      outcome = simulate_try(selection.provider, operation, reserved.reservation)
      context.add_latency!(outcome.fetch(:latency_sec))
      decision = apply_outcome(operation, selection, context, outcome, reserved.reservation)
      context.mark_attempted!(selection.provider.name) if decision.nil?
      decision
    end

    def reserve(selection, operation, runtime_snapshot)
      @state.try_reserve!(
        selection.provider,
        operation,
        expected_revision: runtime_snapshot.revision
      )
    end

    def pick(operation, attempted)
      runtime_snapshot = @state.snapshot
      selection = Router.call(
        operation: operation,
        providers: runtime_snapshot.providers,
        snapshot: runtime_snapshot.soft_goals,
        policy: @policy,
        attempted: attempted
      )
      [selection, runtime_snapshot]
    end

    def apply_outcome(operation, selection, context, outcome, reservation)
      result = outcome.fetch(:result)
      if result == "approved"
        @state.approve!(reservation)
        return complete(operation, selection, context, outcome)
      end
      if result == "expired"
        @state.mark_timeout!(reservation)
        return complete(operation, selection, context, outcome)
      end

      @state.reject!(reservation)
      return complete(operation, selection, context, outcome) if selection.fallback?

      context.add_attempt!(skip_attempt(selection.provider.name, simulation_reason(result), nil))
      nil
    end

    def simulate_try(provider, operation, reservation)
      ProviderInvoker.call(
        client: @simulator,
        provider: provider,
        operation: operation,
        reservation: reservation
      )
    rescue StandardError
      @state.reject!(reservation) if reservation.active?
      raise
    end

    def complete(operation, selection, context, outcome)
      provider = selection.provider
      context.add_attempt!(
        HardConstraints::Attempt.new(
          provider: provider.name,
          decision: "selected",
          reason: selected_reason(selection),
          details: DecisionExplainer.details(
            selection: selection,
            policy: @policy,
            result: outcome.fetch(:result)
          )
        )
      )
      Decision.new(
        operation_id: operation.id,
        selected_provider: provider.name,
        attempts: context.attempts,
        simulated_result: outcome.fetch(:result),
        latency_sec: context.total_latency
      )
    end

    def resolve_unroutable(operation, selection, runtime_snapshot, context)
      return unless @state.current_revision?(runtime_snapshot.revision)

      context.merge_skips!(selection.evaluation.skipped)
      raise InvalidInputError,
            "operation #{operation.id} cannot be routed without violating hard constraints"
    end

    def reservation_failed(selection, reserved, context)
      context.add_attempt!(skip_attempt(selection.provider.name, reserved.reason, reserved.details))
      context.mark_attempted!(selection.provider.name)
      nil
    end

    def validate_online_operation!(operation)
      Routing.assert(operation.is_a?(Operation), "operation must be Routing::Operation")
      raise InvalidInputError, "duplicate operation_id #{operation.id}" if @processed_ids.key?(operation.id)
      return if @last_created_at.nil? || operation.created_at.nil? || operation.created_at >= @last_created_at

      raise InvalidInputError, "operations must be ordered by created_at"
    end

    def skip_attempt(name, reason, details)
      HardConstraints::Attempt.new(provider: name, decision: "skipped", reason: reason, details: details)
    end

    def simulation_reason(result)
      return Simulator::REJECTED if result == "rejected"
      return Simulator::EXPIRED if result == "expired"

      Routing.assert(false, "unexpected simulation result #{result}")
    end

    def selected_reason(selection)
      return FALLBACK_SELECTED if selection.fallback?

      selection.ranking.scores.fetch(selection.provider.name).reason
    end
  end
end
