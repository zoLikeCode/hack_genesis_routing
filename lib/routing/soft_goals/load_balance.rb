# frozen_string_literal: true

module Routing
  module SoftGoals
    class LoadBalance
      KEY = "load_balance"

      def self.call(provider, _operation, _snapshot)
        utilizations = [
          utilization(provider.in_progress_count, provider.in_progress_count_limit),
          utilization(provider.in_progress_amount, provider.in_progress_amount_limit)
        ].compact
        return neutral if utilizations.empty?

        load = utilizations.max.clamp(0.0, 1.0)
        score = 1.0 - load
        Contribution.new(
          name: KEY,
          score: score,
          reason: load >= 0.75 ? Reasons::HIGH_CURRENT_LOAD : Reasons::AVAILABLE_CAPACITY,
          details: "maximum in-progress utilization #{(load * 100).round(2)}%"
        )
      end

      def self.utilization(value, limit)
        return if limit.nil?
        return value.zero? ? 0.0 : 1.0 if limit.zero?

        value.to_f / limit
      end
      private_class_method :utilization

      def self.neutral
        Contribution.new(name: KEY, score: 0.0, reason: Reasons::NEUTRAL)
      end
      private_class_method :neutral
    end
  end
end
