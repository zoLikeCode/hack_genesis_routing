# frozen_string_literal: true

module Routing
  class Engine
    include Recording
    include Reconciliation
    include Setup

    FALLBACK_SELECTED = "fallback_selected"
    CIRCUIT_BREAKER_OPEN = HardConstraints::Reasons::CIRCUIT_BREAKER_OPEN
    STATUS_CHECK_REJECTED = "status_check_rejected"

    attr_reader :state, :status_checker, :status_check_runner, :circuit_breaker,
                :admission, :settlement, :operations, :providers, :policy,
                :runtime_store, :decisions_by_id, :operations_by_id

    def self.call(operations:, providers:, policy:, simulator: nil, state: nil, **) # rubocop:disable Metrics/ParameterLists
      new(operations, providers, policy, simulator, state: state, **).call
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
      initialize_control_plane!
    end

    def call
      return Concurrency::Supervisor.call(self) if concurrent?

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
      remember_operation!(operation, decision)
      persist_runtime!
      decision
    end

    def concurrent?
      @concurrent
    end

    def client
      @simulator
    end

    def remember_operation!(operation, decision)
      @processed_ids[operation.id] = true
      @operations_by_id[operation.id] = operation
      @decisions_by_id[operation.id] = decision
      @last_created_at = operation.created_at unless operation.created_at.nil?
    end

    def assert_operation_admissible!(operation)
      validate_online_operation!(operation)
    end

    def store_decision!(operation_id, decision)
      @decisions_by_id[operation_id] = decision
    end

    def track_operation!(operation)
      validate_online_operation!(operation)
      @processed_ids[operation.id] = true
      @operations_by_id[operation.id] = operation
      @last_created_at = operation.created_at unless operation.created_at.nil?
    end

    def status_cascade_item(settlement)
      operation, previous, provider_name = reconciliation_context(settlement)
      return unless reroutable_reconciliation?(operation, previous, provider_name)

      Concurrency::WorkItem.new(
        operation,
        RouteContext.new(
          attempts: reconciled_attempts(previous, provider_name),
          attempted: reserved_provider_names_for(operation),
          total_latency: previous.latency_sec
        )
      )
    end

    def finalize_status_decision!(settlement)
      operation_id = settlement.fetch("operation_id")
      provider_name = settlement.fetch("provider")
      result = settlement.fetch("result")
      previous = @decisions_by_id.fetch(operation_id)
      Routing.assert(previous.provisional?, "status settlement requires a provisional decision")
      Routing.assert(previous.selected_provider == provider_name,
                     "status settlement provider does not match provisional decision")
      @decisions_by_id[operation_id] = Decision.new(
        operation_id: operation_id,
        selected_provider: provider_name,
        attempts: finalized_status_attempts(previous, provider_name, result),
        simulated_result: result,
        latency_sec: previous.latency_sec,
        final: true
      )
    end

    def persist_runtime!
      @runtime_store&.save(state: @state, status_checker: @status_checker)
    end

    private

    def finalized_status_attempts(previous, provider_name, result)
      previous.attempts.map do |attempt|
        next attempt unless attempt.provider == provider_name && attempt.decision == "selected"

        HardConstraints::Attempt.new(
          provider: provider_name,
          decision: "selected",
          reason: attempt.reason,
          details: "terminal status-check #{result}; reservation settled"
        )
      end
    end

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

    def initialize_control_plane!
      @admission = Admission.new(state: @state, policy: @policy, circuit_breaker: @circuit_breaker)
      @settlement = Settlement.new(
        state: @state,
        policy: @policy,
        status_check_runner: @status_check_runner,
        persist: method(:persist_runtime!)
      )
    end

    def route(operation, context: RouteContext.new)
      Routing.assert(operation.is_a?(Operation), "operation must be Routing::Operation")
      loop do
        decision = route_attempt(operation, context)
        return decision if decision
      end
    end

    def route_attempt(operation, context)
      selection, runtime_snapshot = @admission.pick(operation, context)
      return resolve_unroutable(operation, selection, runtime_snapshot, context) unless selection.routable?

      reserved = @admission.reserve(selection, operation, runtime_snapshot)
      return @admission.handle_stale(context) if reserved.stale?

      context.merge_skips!(selection.evaluation.skipped)
      return @admission.handle_ineligible(selection, reserved, context) unless reserved.reserved?

      dispatch_and_settle(operation, selection, context, reserved.reservation)
    end

    def dispatch_and_settle(operation, selection, context, reservation)
      persist_runtime!
      @state.mark_dispatching!(reservation, at: operation.created_at)
      context.mark_attempted!(selection.provider.name)
      outcome = simulate_try(selection.provider, operation, reservation)
      return settle_failure(operation, selection, context, reservation, outcome) if outcome.is_a?(AdapterError)

      context.add_latency!(outcome.fetch(:latency_sec))
      @settlement.apply_payout(
        operation: operation,
        selection: selection,
        context: context,
        outcome: outcome,
        reservation: reservation,
        timeout_at: timeout_time(operation, context)
      )
    end

    def settle_failure(operation, selection, context, reservation, error)
      @settlement.apply_failure(
        operation: operation,
        selection: selection,
        context: context,
        reservation: reservation,
        error: error,
        timeout_at: timeout_time(operation, context)
      )
    end

    def resolve_unroutable(operation, selection, runtime_snapshot, context)
      return unless @state.current_revision?(runtime_snapshot.revision)

      context.merge_skips!(selection.evaluation.skipped)
      raise InvalidInputError,
            "operation #{operation.id} cannot be routed without violating hard constraints"
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
  end
end
