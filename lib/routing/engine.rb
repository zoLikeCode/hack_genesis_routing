# frozen_string_literal: true

module Routing
  class Engine
    include Recording

    FALLBACK_SELECTED = "fallback_selected"

    attr_reader :state, :status_checker, :status_check_runner

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
      @state = state || RuntimeState.new(providers, metrics_config: policy.metrics, policy: policy)
      Routing.assert(@state.is_a?(RuntimeState), "state must be Routing::RuntimeState")
      Routing.assert(@state.providers.equal?(providers), "runtime state must own the provider pool")
      @status_checker = build_status_checker
      @status_check_runner = StatusCheckRunner.new(checker: @status_checker)
      @processed_ids = {}
      @last_created_at = nil
    end

    def call
      decisions = @operations.each_with_object([]) { |operation, result| result << route_one(operation) }
      @status_check_runner.drain
      decisions
    end

    def route_one(operation)
      validate_online_operation!(operation)
      run_due_status_checks(operation)
      decision = route(operation)
      @processed_ids[operation.id] = true
      @last_created_at = operation.created_at unless operation.created_at.nil?
      decision
    end

    private

    def build_status_checker
      StatusChecker.new(
        state: @state,
        providers: @providers,
        client: @simulator,
        config: @policy.status_check
      )
    end

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
      record_metric(operation, selection.provider, outcome)
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
        @status_check_runner.schedule(reservation, timed_out_at: timeout_time(operation, context))
        return complete(operation, selection, context, outcome)
      end

      @state.reject!(reservation)
      return complete(operation, selection, context, outcome) if selection.fallback?

      context.add_attempt!(skip_attempt(selection.provider.name, simulation_reason(result), nil))
      nil
    end

    def simulate_try(provider, operation, reservation)
      finished = false
      outcome = ProviderInvoker.call(
        client: @simulator,
        provider: provider,
        operation: operation,
        reservation: reservation
      )
      finished = true
      outcome
    ensure
      record_failed_try(operation, provider, reservation) unless finished
    end

    def complete(operation, selection, context, outcome)
      record_considered_skips!(selection, context)
      context.add_attempt!(selected_attempt(selection, outcome))
      Decision.new(
        operation_id: operation.id,
        selected_provider: selection.provider.name,
        attempts: context.attempts,
        simulated_result: outcome.fetch(:result),
        latency_sec: context.total_latency
      )
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

    def run_due_status_checks(operation)
      @status_check_runner.run_due(now: operation.created_at) unless operation.created_at.nil?
    end

    def timeout_time(operation, context)
      return Time.now if operation.created_at.nil?

      operation.created_at + context.total_latency
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
