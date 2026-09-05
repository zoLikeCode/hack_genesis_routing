# frozen_string_literal: true

module Routing
  module SoftGoals
    class Conversion
      KEY = "conversion"
      METRICS = %w[catalog.conversion_24h].freeze

      def self.call(provider, _operation, _snapshot, _policy = nil)
        value = provider.conversion_24h
        return Contribution.new(name: KEY, score: 0.0, reason: Reasons::NEUTRAL) if value.nil?

        score = value.to_f.clamp(0.0, 1.0)
        Contribution.new(
          name: KEY,
          score: score,
          reason: Reasons::HIGHER_CONVERSION,
          details: "conversion_24h #{score}"
        )
      end
    end
  end
end
