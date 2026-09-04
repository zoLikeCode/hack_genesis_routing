# frozen_string_literal: true

module Routing
  module SoftGoals
    class AmountBand
      KEY = "amount_band"

      def self.call(provider, operation, _snapshot)
        minimum = provider.limit_amount_min
        maximum = provider.limit_amount_max
        return neutral if minimum.nil? || maximum.nil?

        width = maximum - minimum
        score = if width.zero?
                  exact_score(operation.amount, minimum)
                else
                  centered_score(operation.amount, minimum, maximum)
                end
        Contribution.new(
          name: KEY,
          score: score,
          reason: Reasons::AMOUNT_BAND_FIT,
          details: "amount #{operation.amount} within preferred band #{minimum}..#{maximum}"
        )
      end

      def self.centered_score(amount, minimum, maximum)
        midpoint = (minimum + maximum).to_f / 2
        half_width = (maximum - minimum).to_f / 2
        (1.0 - ((amount - midpoint).abs / half_width)).clamp(0.0, 1.0)
      end
      private_class_method :centered_score

      def self.exact_score(amount, expected)
        amount == expected ? 1.0 : 0.0
      end
      private_class_method :exact_score

      def self.neutral
        Contribution.new(name: KEY, score: 0.0, reason: Reasons::NEUTRAL)
      end
      private_class_method :neutral
    end
  end
end
