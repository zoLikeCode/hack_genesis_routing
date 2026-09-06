# frozen_string_literal: true

module Routing
  class Router
    Selection = Data.define(:provider, :evaluation, :ranking, :fallback_used) do
      def routable?
        !provider.nil?
      end

      def fallback?
        fallback_used
      end
    end

    def self.call(operation:, providers:, snapshot:, policy:, attempted: [], temporarily_excluded: [])
      new(operation, providers, snapshot, policy, attempted, temporarily_excluded).call
    end

    def initialize(operation, providers, snapshot, policy, attempted, temporarily_excluded)
      @operation = operation
      @providers = normalize_providers(providers)
      @snapshot = snapshot
      @policy = policy
      validate!
      @attempted = normalize_names(attempted, "attempted")
      @temporarily_excluded = normalize_names(temporarily_excluded, "temporarily_excluded")
    end

    def call
      evaluation = HardConstraints::Filter.call(
        operation: @operation,
        providers: remaining_providers,
        fallback: @policy.fallback_provider
      )
      ranking = SoftGoals::Ranker.call(
        eligible: evaluation.eligible,
        operation: @operation,
        snapshot: @snapshot,
        policy: @policy
      )
      preferred = Selector.call(ranking: ranking, operation: @operation, policy: @policy)
      fallback = preferred.nil? ? evaluation.fallback : nil

      Selection.new(
        provider: preferred || fallback,
        evaluation: evaluation,
        ranking: ranking,
        fallback_used: !fallback.nil?
      )
    end

    private

    def normalize_providers(providers)
      Routing.assert(providers.respond_to?(:each), "providers must be enumerable")
      providers.to_a
    end

    def normalize_names(names, label)
      Routing.assert(names.respond_to?(:to_a), "#{label} must be enumerable")
      list = names.to_a
      Routing.assert(list.all? { |name| name.is_a?(String) && !name.empty? },
                     "#{label} provider names must be non-empty strings")
      unknown = list.uniq - @providers.map(&:name)
      Routing.assert(unknown.empty?, "#{label} contains unknown providers: #{unknown.join(', ')}")
      list.uniq.freeze
    end

    def validate!
      Routing.assert(@operation.is_a?(Operation), "operation must be Routing::Operation")
      Routing.assert(@providers.all?(Provider), "providers must be Provider objects")
      Routing.assert(@snapshot.is_a?(SoftGoals::Snapshot), "snapshot must be SoftGoals::Snapshot")
      Routing.assert(@policy.is_a?(Policy), "policy must be Routing::Policy")
    end

    def remaining_providers
      excluded = @attempted + @temporarily_excluded
      @providers.reject { |provider| excluded.include?(provider.name) }
    end
  end
end
