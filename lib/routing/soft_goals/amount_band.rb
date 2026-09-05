# frozen_string_literal: true

module Routing
  module SoftGoals
    class AmountBand
      KEY = "amount_band"
      METRICS = %w[operation.amount catalog.limit_amount_max].freeze

      def self.call(provider, operation, _snapshot, _policy = nil)
        maximum = provider.limit_amount_max
        return neutral if maximum.nil? || !maximum.positive?

        ratio = (operation.amount.to_f / maximum).clamp(0.0, 1.0)
        Contribution.new(
          name: KEY,
          score: ratio,
          reason: Reasons::AMOUNT_BAND_FIT,
          details: "amount #{operation.amount} is #{format_pct(ratio * 100)}% of limit_amount_max #{maximum}"
        )
      end

      def self.format_pct(value)
        value.round(2)
      end
      private_class_method :format_pct

      def self.neutral
        Contribution.new(name: KEY, score: 0.0, reason: Reasons::NEUTRAL)
      end
      private_class_method :neutral
    end
  end
end
