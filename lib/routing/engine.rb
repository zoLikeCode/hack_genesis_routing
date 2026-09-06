# frozen_string_literal: true

module Routing
  class Engine
    include Recording
    include Reconciliation
    include Setup

    FALLBACK_SELECTED = "fallback_selected"
    CIRCUIT_BREAKER_OPEN = "circuit_breaker_open"
    STATUS_CHECK_REJECTED = "status_check_rejected"

    attr_reader :state, :status_checker, :status_check_runner, :circuit_breaker

    def self.call(operations:, providers:, policy:, simulator: nil, state: nil)
      new(operations, providers, policy, simulator, state: state).call
    end

    def initialize(operations, providers, policy, simulator = nil, **options)
      validate_engine_inputs!(operations, providers, policy)
      @operations = operations
      @providers = providers
      @policy = policy
      @policy.validate_provider_targets!(@providers)
      apply_default_requests_per_minute_limit!
      initialize_runtime!(simulator, options)
      initialize_status_checks!
      initialize_tracking!
    end

    def call
      @operations.each { |operation| route_one(operation) }
      @status_check_runner.drain do |result|
        handle_status_settlements(result)
        persist_runtime!
      end
      @operations.map { |operation| @decisions_by_id.fetch(operation.id) }
    end

    def route_one(operation)
      validate_online_operation!(operation)
      run_due_status_checks(operation)
      decision = route(operation)
      @processed_ids[operation.id] = true
      @operations_by_id[operation.id] = operation
      @decisions_by_id[operation.id] = decision
      @last_created_at = operation.created_at unless operation.created_at.nil?
      persist_runtime!
      decision
    end

    private

    def build_status_checker
      StatusChecker.new(
        state: @state,
        providers: @providers,
        client: @simulator,
        config: @policy.status_check,
        circuit_breaker: @circuit_breaker
      )
    end

    def apply_default_requests_per_minute_limit!
      limit = @policy.default_requests_per_minute_limit
      @providers.apply_default_requests_per_minute_limit!(limit) unless limit.nil?
    end

    def route(operation, context: RouteContext.new)
      Routing.assert(operation.is_a?(Operation), "operation must be Routing::Operation")
      exclude_open_circuits!(context)

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

      persist_runtime!
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
      @state.record_outcome!(
        reservation: reservation, operation: operation, status: result,
        latency_sec: outcome.fetch(:latency_sec)
      )
      return complete(operation, selection, context, outcome) if result == "approved"

      if result == "expired"
        @status_check_runner.schedule(reservation, timed_out_at: timeout_time(operation, context))
        return complete(operation, selection, context, outcome)
      end

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
