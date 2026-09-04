# frozen_string_literal: true

module Routing
  module SoftGoals
    class HistoricalQuality
      KEY = "historical_quality"

      def self.call(provider, operation, snapshot, policy = nil)
        observations = observations_for(snapshot, provider)
        return neutral if observations.nil?

        quality = Metrics::Catalog.call(
          observations: observations,
          provider: provider,
          operation: operation,
          config: config_for(policy, provider)
        )
        Contribution.new(
          name: KEY,
          score: quality.score,
          reason: Reasons::HISTORICAL_QUALITY,
          details: details(quality)
        )
      end

      def self.observations_for(snapshot, provider)
        return snapshot.metrics.observations_for(provider.name) unless snapshot.metrics.nil?
        return snapshot.history.observations_for(provider.name) unless snapshot.history.nil?

        nil
      end
      private_class_method :observations_for

      def self.config_for(policy, provider)
        return if policy.nil?

        policy.metrics_for(provider)
      end
      private_class_method :config_for

      def self.details(quality)
        approval = (quality.approval_rate * 100).round(1)
        timeout = (quality.timeout_rate * 100).round(1)
        availability = (quality.availability * 100).round(1)
        latency = quality.p90_latency_sec.nil? ? "unknown" : quality.p90_latency_sec.round(1)
        "scope=#{quality.scope} n=#{quality.sample_size} approval=#{approval}% " \
          "timeout=#{timeout}% availability=#{availability}% p90_latency_sec=#{latency}"
      end
      private_class_method :details

      def self.neutral
        Contribution.new(name: KEY, score: 0.0, reason: Reasons::NEUTRAL, details: "history unavailable")
      end
      private_class_method :neutral
    end
  end
end
