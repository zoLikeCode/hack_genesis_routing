# frozen_string_literal: true

module Routing
  module SoftGoals
    class CountShare
      KEY = "count_share"
      METRICS = %w[session.count_share_pct catalog.traffic_percentage].freeze

      def self.score_all(candidates:, snapshot:)
        ShareFit.call(
          candidates: candidates, totals: snapshot.count_totals,
          targets: snapshot.count_targets, increment: ->(_provider) { 1 }
        )
      end

      def self.from_result(result)
        Contribution.new(
          name: KEY, score: result.score, reason: Reasons::COUNT_SHARE_DEFICIT,
          details: details(result)
        )
      end

      def self.details(result)
        "share #{pct(result.before_share)}% -> #{pct(result.after_share)}% target #{pct(result.target_share)}%; " \
          "squared_error #{result.before_error.round(6)} -> #{result.after_error.round(6)}"
      end
      private_class_method :details

      def self.pct(value)
        (value * 100).round(2)
      end
      private_class_method :pct
    end
  end
end
