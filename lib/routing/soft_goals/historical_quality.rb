# frozen_string_literal: true

module Routing
  module SoftGoals
    class HistoricalQuality
      KEY = "historical_quality"

      def self.call(provider, operation, snapshot)
        history = snapshot.history
        return neutral if history.nil?

        quality = history.quality(provider: provider, operation: operation)
        Contribution.new(
          name: KEY,
          score: quality.score,
          reason: Reasons::HISTORICAL_QUALITY,
          details: details(quality)
        )
      end

      def self.details(quality)
        approval = (quality.approval_rate * 100).round(1)
        timeout = (quality.timeout_rate * 100).round(1)
        latency = quality.p90_latency_sec.nil? ? "unknown" : quality.p90_latency_sec.round(1)
        "scope=#{quality.scope} n=#{quality.sample_size} approval=#{approval}% " \
          "timeout=#{timeout}% p90_latency_sec=#{latency}"
      end
      private_class_method :details

      def self.neutral
        Contribution.new(name: KEY, score: 0.0, reason: Reasons::NEUTRAL, details: "history unavailable")
      end
      private_class_method :neutral
    end
  end
end
