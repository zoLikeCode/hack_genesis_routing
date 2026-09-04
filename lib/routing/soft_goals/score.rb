# frozen_string_literal: true

module Routing
  module SoftGoals
    class Score
      attr_reader :total, :base_total, :health, :contributions, :reason, :metrics

      def initialize(total:, contributions:, reason:, **options)
        health = options.fetch(:health, 1.0)
        metrics = options[:metrics]
        base_total = options.fetch(:base_total, total)
        Routing.assert(total.is_a?(Numeric), "score total must be numeric")
        Routing.assert(contributions.is_a?(Array) && contributions.all?(Contribution),
                       "score contributions must be Contribution objects")
        Routing.assert(reason.is_a?(String) && !reason.empty?, "score reason required")
        Routing.assert(health.is_a?(Numeric) && health >= 0, "score health must be non-negative")
        Routing.assert(metrics.nil? || metrics.is_a?(Metrics::Vector), "score metrics must be Metrics::Vector")
        @total = total
        @base_total = base_total
        @health = health
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
