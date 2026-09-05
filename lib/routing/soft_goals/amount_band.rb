# frozen_string_literal: true

module Routing
  module SoftGoals
    class AmountBand
      KEY = "amount_band"
      METRICS = %w[operation.amount catalog.amount_band_preferences].freeze

      def self.call(provider, operation, _snapshot, policy = nil)
        Routing.assert(policy.is_a?(Policy), "amount_band requires Policy")
        score = policy.amount_band_score(provider, operation.amount)
        Contribution.new(
          name: KEY,
          score: score,
          reason: Reasons::AMOUNT_BAND_FIT,
          details: "amount #{operation.amount} configured preference score #{score.round(3)}"
        )
      end
    end
  end
end
