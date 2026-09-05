# frozen_string_literal: true

module Routing
  class Report
    class ProviderStats
      def self.call(runtime_state:, providers:, policy:, names:, as_of: nil)
        new(runtime_state, providers, policy, names, as_of).call
      end

      def initialize(runtime_state, providers, policy, names, as_of)
        @runtime_state = runtime_state
        @providers = providers
        @policy = policy
        @names = names
        @as_of = as_of
      end

      def call
        return {} if @runtime_state.nil?

        @names.to_h { |name| [name, entry(name)] }
      end

      private

      def entry(name)
        provider = @providers.fetch(name)
        vector = Metrics::Catalog.summarize(
          observations: @runtime_state.metrics.observations_for(name),
          provider: provider, config: @policy.metrics_for(provider), as_of: @as_of
        )
        serialize(vector)
      end

      def serialize(vector)
        identity_fields(vector).merge(outcome_fields(vector), timing_fields(vector))
      end

      def identity_fields(vector)
        {
          "conversion_estimate" => vector.score.round(4),
          "source" => vector.source,
          "scope" => vector.scope,
          "sample_size" => vector.sample_size,
          "prior" => vector.prior.round(4)
        }
      end

      def outcome_fields(vector)
        {
          "initial_approved" => vector.initial_approved_count,
          "initial_rejected" => vector.initial_rejected_count,
          "initial_timeouts" => vector.initial_timeout_count,
          "initial_conversion" => rounded(vector.initial_approval_rate),
          "initial_timeout_rate" => rounded(vector.initial_timeout_rate),
          "initial_refusal_rate" => rounded(vector.initial_refusal_rate),
          "initial_answer_success" => rounded(vector.initial_acceptance),
          "final_approved" => vector.final_approved_count,
          "final_rejected" => vector.final_rejected_count,
          "unresolved" => vector.unresolved_count
        }
      end

      def timing_fields(vector)
        {
          "p90_initial_latency_sec" => vector.p90_initial_latency_sec,
          "latency_sample_size" => vector.latency_sample_size,
          "last_observation_at" => vector.last_observation_at&.iso8601,
          "data_age_sec" => vector.data_age_sec&.round(1)
        }
      end

      def rounded(value)
        value&.round(4)
      end
    end
  end
end
