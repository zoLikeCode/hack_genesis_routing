# frozen_string_literal: true

module Routing
  class Engine
    FALLBACK_SELECTED = "fallback_selected"

    def self.call(operations:, providers:, policy:, simulator: nil)
      new(operations, providers, policy, simulator).call
    end

    def initialize(operations, providers, policy, simulator)
      Routing.assert(operations.respond_to?(:each), "operations must be enumerable")
      Routing.assert(providers.is_a?(ProviderPool), "providers must be a ProviderPool")
      Routing.assert(policy.is_a?(Policy), "policy must be Routing::Policy")
      @operations = operations
      @providers = providers
      @policy = policy
      @simulator = simulator || Simulator.new(seed: policy.simulation_seed)
      @snapshot = SoftGoals::Snapshot.from_providers(providers)
    end

    def call
      @operations.map { |operation| route(operation) }
    end

    private

    def route(operation)
      Routing.assert(operation.is_a?(Operation), "operation must be Routing::Operation")
      attempts = []
      attempted = []

      loop do
        selection = pick(operation, attempted)
        merge_skips(attempts, selection.evaluation.skipped)
        return unroutable(operation, attempts) unless selection.routable?

        decision = try_selection(operation, selection, attempts)
        return decision if decision

        attempted += [selection.provider.name]
      end
    end

    def pick(operation, attempted)
      Router.call(
        operation: operation,
        providers: @providers,
        snapshot: @snapshot,
        policy: @policy,
        attempted: attempted
      )
    end

    def try_selection(operation, selection, attempts)
      outcome = simulate_try(selection.provider, operation)
      return complete(operation, selection, attempts, outcome) if keep_selection?(selection, outcome)

      attempts << skip_attempt(selection.provider.name, simulation_reason(outcome.fetch(:result)), nil)
      nil
    end

    def keep_selection?(selection, outcome)
      selection.fallback? || outcome.fetch(:result) == "approved"
    end

    def simulate_try(provider, operation)
      @providers.reserve!(provider, operation)
      outcome = @simulator.call(provider)
      @providers.release!(provider, operation.amount)
      outcome
    end

    def complete(operation, selection, attempts, outcome)
      provider = selection.provider
      if outcome.fetch(:result) == "approved"
        @providers.commit_approved!(provider, operation.amount)
        @snapshot.record!(provider.name, operation.amount)
      end
      attempts << HardConstraints::Attempt.new(
        provider: provider.name,
        decision: "selected",
        reason: selected_reason(selection),
        details: selected_details(selection.ranking)
      )
      Decision.new(
        operation_id: operation.id,
        selected_provider: provider.name,
        attempts: attempts,
        simulated_result: outcome.fetch(:result),
        latency_sec: outcome.fetch(:latency_sec)
      )
    end

    def unroutable(operation, attempts)
      Decision.new(
        operation_id: operation.id,
        selected_provider: @policy.fallback_provider,
        attempts: attempts,
        simulated_result: "rejected",
        latency_sec: 0
      )
    end

    def merge_skips(attempts, skipped)
      seen = attempts.map { |attempt| [attempt.provider, attempt.reason] }
      skipped.each do |attempt|
        next if seen.include?([attempt.provider, attempt.reason])

        attempts << attempt
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

    def selected_details(ranking)
      return ranking.notes.join("; ") unless ranking.notes.empty?

      kinds = ranking.conflicts.map(&:kind).uniq
      kinds.join("; ") unless kinds.empty?
    end
  end
end
