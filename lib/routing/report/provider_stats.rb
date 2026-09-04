# frozen_string_literal: true

module Routing
  class Report
    class ProviderStats
      AVAILABILITY_WARN = 0.75

      def self.call(runtime_state:, providers:, policy:, names:)
        new(runtime_state, providers, policy, names).call
      end

      def self.recommendations(metrics, policy)
        metrics.filter_map { |name, row| availability_rec(name, row, policy) }
      end

      def self.conversion_recs(history, outcomes)
        return [] if history.nil?

        outcomes.filter_map { |name, current| conversion_rec(history, name, current) }
      end

      def initialize(runtime_state, providers, policy, names)
        @runtime_state = runtime_state
        @providers = providers
        @policy = policy
        @names = names
      end

      def call
        return {} if @runtime_state.nil?

        @names.to_h { |name| [name, entry(name)] }
      end

      def self.availability_rec(name, row, policy)
        return if row.fetch("sample_size").zero?
        return unless row.fetch("availability") < AVAILABILITY_WARN

        pct = (row.fetch("availability") * 100).round(1)
        "#{name} availability is #{pct}% - raise #{health_knob(name, policy)} or reduce traffic_percentage"
      end
      private_class_method :availability_rec

      def self.health_knob(name, policy)
        profile = policy.profile_for(name)
        return "metrics.multipliers.health.exponent" if profile.nil?

        "profiles.#{profile}.metrics.multipliers.health.exponent"
      end
      private_class_method :health_knob

      def self.conversion_rec(history, name, current)
        baseline = history[name]
        return if baseline.nil? || current.fetch("attempted").zero?

        historical = baseline.fetch("conversion") * 100
        current_pct = current.fetch("approval_pct")
        return unless historical - current_pct >= Report::SHARE_GAP

        "#{name} approval_pct is #{current_pct}% vs historical #{historical.round(1)}% - review its profile weights"
      end
      private_class_method :conversion_rec

      private

      def entry(name)
        provider = @providers.fetch(name)
        vector = Metrics::Catalog.summarize(
          observations: @runtime_state.metrics.observations_for(name),
          provider: provider,
          config: @policy.metrics_for(provider)
        )
        serialize(vector)
      end

      def serialize(vector)
        {
          "sample_size" => vector.sample_size,
          "approval_rate" => vector.approval_rate.round(4),
          "availability" => vector.availability.round(4),
          "acceptance" => vector.acceptance.round(4),
          "health" => vector.health.round(4),
          "timeout_rate" => vector.timeout_rate.round(4),
          "refusal_rate" => vector.refusal_rate.round(4),
          "p90_latency_sec" => vector.p90_latency_sec
        }
      end
    end
  end
end
