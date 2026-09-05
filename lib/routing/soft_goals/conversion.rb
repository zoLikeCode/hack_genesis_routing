# frozen_string_literal: true

module Routing
  module SoftGoals
    class Conversion
      KEY = "conversion"
      METRICS = %w[catalog.conversion_24h window.initial_conversion].freeze

      def self.call(provider, operation, snapshot, policy = nil)
        observations = if !snapshot.metrics.nil?
                         snapshot.metrics.observations_for(provider.name)
                       elsif !snapshot.history.nil?
                         snapshot.history.observations_for(provider.name)
                       else
                         []
                       end
        vector = Metrics::Catalog.call(
          observations: observations, provider: provider, operation: operation,
          config: policy&.metrics_for(provider)
        )
        from_vector(vector)
      end

      def self.from_vector(vector)
        Routing.assert(vector.is_a?(Metrics::Vector), "conversion requires Metrics::Vector")
        Contribution.new(
          name: KEY,
          score: vector.score,
          reason: Reasons::HIGHER_CONVERSION,
          details: "estimate #{vector.score.round(4)} source=#{vector.source} " \
                   "scope=#{vector.scope} n=#{vector.sample_size} prior=#{vector.prior.round(4)}"
        )
      end
    end
  end
end
