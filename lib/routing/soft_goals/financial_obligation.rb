# frozen_string_literal: true

module Routing
  module SoftGoals
    class FinancialObligation
      KEY = "financial_obligation"
      METRICS = %w[
        runtime.daily_approved_amount
        catalog.daily_turnover_min
        catalog.daily_turnover_max
        operation.amount
      ].freeze
      SOFT_MAX_START = 0.8

      def self.call(provider, operation, _snapshot, _policy = nil)
        projected = provider.daily_approved_amount + operation.amount
        boost = min_boost(provider, projected)
        penalty = max_penalty(provider, projected)
        score = ((1.0 + boost - penalty) / 2.0).clamp(0.0, 1.0)
        Contribution.new(
          name: KEY,
          score: score,
          reason: reason_for(boost, penalty),
          details: details_for(provider, projected)
        )
      end

      def self.min_boost(provider, projected)
        min = provider.daily_turnover_min
        return 0.0 if min.nil? || min.zero?
        return 0.0 if projected >= min

        ((min - projected) / min.to_f).clamp(0.0, 1.0)
      end
      private_class_method :min_boost

      def self.max_penalty(provider, projected)
        max = provider.daily_turnover_max
        return 0.0 if max.nil? || max.zero?

        ratio = projected / max.to_f
        return 0.0 if ratio <= SOFT_MAX_START

        span = 1.0 - SOFT_MAX_START
        ((ratio - SOFT_MAX_START) / span).clamp(0.0, 1.0)
      end
      private_class_method :max_penalty

      def self.reason_for(boost, penalty)
        return Reasons::TURNOVER_BELOW_MINIMUM if boost.positive? && boost >= penalty
        return Reasons::TURNOVER_ABOVE_SOFT_MAX if penalty.positive?

        Reasons::NEUTRAL
      end
      private_class_method :reason_for

      def self.details_for(provider, projected)
        "approved #{provider.daily_approved_amount} projected #{projected} " \
          "min #{provider.daily_turnover_min} max #{provider.daily_turnover_max}"
      end
      private_class_method :details_for
    end
  end
end
