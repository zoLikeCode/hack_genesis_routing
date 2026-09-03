# frozen_string_literal: true

module Routing
  module SoftGoals
    class CascadePriority
      KEY = "cascade_priority"

      def self.call(provider, _operation, _snapshot)
        priority = provider.priority
        return Contribution.new(name: KEY, score: 0.0, reason: Reasons::NEUTRAL) if priority.nil?

        Routing.assert(priority.positive?, "priority must be a positive integer")
        score = (1.0 / priority).clamp(-1.0, 1.0)
        Contribution.new(
          name: KEY,
          score: score,
          reason: Reasons::CASCADE_PRIORITY,
          details: "priority #{priority}"
        )
      end
    end
  end
end
