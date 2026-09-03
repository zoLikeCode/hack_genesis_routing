# frozen_string_literal: true

module Routing
  module SoftGoals
    class Score
      attr_reader :total, :contributions, :reason

      def initialize(total:, contributions:, reason:)
        Routing.assert(total.is_a?(Numeric), "score total must be numeric")
        Routing.assert(contributions.is_a?(Array) && contributions.all?(Contribution),
                       "score contributions must be Contribution objects")
        Routing.assert(reason.is_a?(String) && !reason.empty?, "score reason required")
        @total = total
        @contributions = contributions
        @reason = reason
      end

      def contribution(name)
        contributions.find { |item| item.name == name }
      end
    end
  end
end
