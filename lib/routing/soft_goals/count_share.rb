# frozen_string_literal: true

module Routing
  module SoftGoals
    class CountShare
      KEY = "count_share"
      METRICS = %w[session.count_share_pct catalog.traffic_percentage].freeze

      def self.call(provider, _operation, snapshot, _policy = nil)
        actual = snapshot.count_share_pct(provider.name)
        target = provider.traffic_percentage
        score = SoftGoals.deficit_score(target, actual)
        Contribution.new(
          name: KEY,
          score: score,
          reason: reason_for(score),
          details: "actual #{format_pct(actual)}% vs target #{format_pct(target)}%"
        )
      end

      def self.reason_for(score)
        if score.positive?
          Reasons::COUNT_SHARE_DEFICIT
        elsif score.negative?
          Reasons::COUNT_SHARE_OVER_TARGET
        else
          Reasons::NEUTRAL
        end
      end
      private_class_method :reason_for

      def self.format_pct(value)
        value.to_f.round(2)
      end
      private_class_method :format_pct
    end
  end
end
