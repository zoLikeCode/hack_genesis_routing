# frozen_string_literal: true

module Routing
  module SoftGoals
    class Contribution
      attr_reader :name, :score, :reason, :details

      def initialize(name:, score:, reason:, details: nil)
        Routing.assert(name.is_a?(String) && !name.empty?, "contribution name required")
        Routing.assert(score.is_a?(Numeric), "contribution score must be numeric")
        Routing.assert(score.between?(0.0, 1.0), "contribution score must be in [0, 1]")
        Routing.assert(reason.is_a?(String) && !reason.empty?, "contribution reason required")
        @name = name
        @score = score
        @reason = reason
        @details = details
      end
    end
  end
end
