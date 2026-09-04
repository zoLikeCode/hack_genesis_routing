# frozen_string_literal: true

module Routing
  module SoftGoals
    class VolumeShare
      KEY = "volume_share"

      def self.call(provider, _operation, snapshot, _policy = nil)
        target = provider.volume_share_pct
        return unset if target.nil?

        actual = snapshot.volume_share_pct(provider.name)
        score = SoftGoals.deficit_score(target, actual)
        Contribution.new(
          name: KEY,
          score: score,
          reason: reason_for(score),
          details: "actual #{format_pct(actual)}% vs target #{format_pct(target)}%"
        )
      end

      def self.unset
        Contribution.new(name: KEY, score: 0.0, reason: Reasons::NEUTRAL)
      end
      private_class_method :unset

      def self.reason_for(score)
        if score.positive?
          Reasons::VOLUME_SHARE_DEFICIT
        elsif score.negative?
          Reasons::VOLUME_SHARE_OVER_TARGET
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
