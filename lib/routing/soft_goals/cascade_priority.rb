# frozen_string_literal: true

module Routing
  module SoftGoals
    class CascadePriority
      KEY = "cascade_priority"
      METRICS = %w[catalog.priority].freeze

      def self.score_all(providers:)
        defined = providers.filter_map(&:priority).uniq.sort
        levels = defined + (providers.any? { |provider| provider.priority.nil? } ? [nil] : [])
        return providers.to_h { |provider| [provider.name, 1.0] } if levels.one?

        providers.to_h do |provider|
          index = levels.index(provider.priority)
          [provider.name, 1.0 - (index.to_f / (levels.size - 1))]
        end
      end

      def self.from_score(provider, score)
        Contribution.new(
          name: KEY, score: score, reason: Reasons::CASCADE_PRIORITY,
          details: "priority #{provider.priority || 'unset'} score #{score.round(3)}"
        )
      end
    end
  end
end
