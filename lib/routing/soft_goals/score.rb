# frozen_string_literal: true

module Routing
  module SoftGoals
    class Score
      attr_reader :total, :contributions, :reason, :metrics

      def initialize(total:, contributions:, reason:, **options)
        metrics = options[:metrics]
        Routing.assert(total.is_a?(Numeric) && total.between?(0.0, 1.0), "score total must be in [0, 1]")
        Routing.assert(contributions.is_a?(Array) && contributions.all?(Contribution),
                       "score contributions must be Contribution objects")
        Routing.assert(reason.is_a?(String) && !reason.empty?, "score reason required")
        Routing.assert(metrics.nil? || metrics.is_a?(Metrics::Vector), "score metrics must be Metrics::Vector")
        @total = total
        @contributions = contributions
        @reason = reason
        @metrics = metrics
      end

      def contribution(name)
        contributions.find { |item| item.name == name }
      end
    end
  end
end
