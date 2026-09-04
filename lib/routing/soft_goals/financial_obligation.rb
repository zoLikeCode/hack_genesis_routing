# frozen_string_literal: true

module Routing
  module SoftGoals
    class FinancialObligation
      KEY = "financial_obligation"
      SOFT_MAX_START = 0.8

      def self.call(provider, operation, _snapshot)
        boost = min_boost(provider)
        penalty = max_penalty(provider, operation)
        score = (boost + penalty).clamp(-1.0, 1.0)
        Contribution.new(
          name: KEY,
          score: score,
          reason: reason_for(boost, penalty),
          details: details_for(provider, operation)
        )
      end

      def self.min_boost(provider)
        min = provider.daily_turnover_min
        return 0.0 if min.nil? || min.zero?
        return 0.0 if provider.daily_approved_amount >= min

        ((min - provider.daily_approved_amount) / min.to_f).clamp(0.0, 1.0)
      end
      private_class_method :min_boost

      def self.max_penalty(provider, operation)
        max = provider.daily_turnover_max
        return 0.0 if max.nil? || max.zero?

        projected = provider.daily_approved_amount + operation.amount
        ratio = projected / max.to_f
        return 0.0 if ratio <= SOFT_MAX_START

        span = 1.0 - SOFT_MAX_START
        -((ratio - SOFT_MAX_START) / span).clamp(0.0, 1.0)
      end
      private_class_method :max_penalty

      def self.reason_for(boost, penalty)
        return Reasons::TURNOVER_BELOW_MINIMUM if boost.positive? && boost >= penalty.abs
        return Reasons::TURNOVER_ABOVE_SOFT_MAX if penalty.negative?

        Reasons::NEUTRAL
      end
      private_class_method :reason_for

      def self.details_for(provider, operation)
        projected = provider.daily_approved_amount + operation.amount
        "approved #{provider.daily_approved_amount} projected #{projected} " \
          "min #{provider.daily_turnover_min} max #{provider.daily_turnover_max}"
      end
      private_class_method :details_for
    end
  end
end
