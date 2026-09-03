# frozen_string_literal: true

module Routing
  class Selector
    def self.call(ranking:, operation:, policy:)
      Routing.assert(ranking.is_a?(SoftGoals::Ranking), "ranking must be SoftGoals::Ranking")
      Routing.assert(operation.is_a?(Operation), "operation must be Routing::Operation")
      Routing.assert(policy.is_a?(Policy), "policy must be Routing::Policy")
      ranking.preferred
    end
  end
end
