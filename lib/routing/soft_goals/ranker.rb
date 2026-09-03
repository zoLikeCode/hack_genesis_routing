# frozen_string_literal: true

module Routing
  module SoftGoals
    class Ranker
      LAST_PRIORITY = 100

      def self.call(eligible:, operation:, snapshot:, policy:)
        new(eligible, operation, snapshot, policy).call
      end

      def initialize(eligible, operation, snapshot, policy)
        Routing.assert(eligible.is_a?(Array), "eligible must be an Array")
        @eligible = eligible
        @operation = operation
        @snapshot = snapshot
        @policy = policy
      end

      def call
        validate!
        return empty_ranking if @eligible.empty?

        scores = score_all
        Ranking.new(
          ordered: sort_eligible(scores),
          scores: scores,
          conflicts: detect_conflicts(scores),
          notes: unmet_notes
        )
      end

      private

      def validate!
        Routing.assert(@operation.is_a?(Operation), "operation must be Routing::Operation")
        Routing.assert(@snapshot.is_a?(Snapshot), "snapshot must be SoftGoals::Snapshot")
        Routing.assert(@policy.is_a?(Policy), "policy must be Routing::Policy")
        Routing.assert(@eligible.all?(Provider), "eligible must be Provider objects")
      end

      def empty_ranking
        Ranking.new(ordered: [], scores: {}, conflicts: unmet_conflicts, notes: unmet_notes)
      end

      def score_all
        reason = @eligible.one? ? Reasons::ONLY_ELIGIBLE_PROVIDER : Reasons::HIGHEST_SOFT_SCORE
        @eligible.to_h { |provider| [provider.name, score_provider(provider, reason)] }
      end

      def score_provider(provider, reason)
        contributions = enabled_goals.map { |goal| goal.call(provider, @operation, @snapshot) }
        total = contributions.sum { |item| @policy.weight_for(item.name) * item.score }
        Score.new(total: total, contributions: contributions, reason: reason)
      end

      def sort_eligible(scores)
        @eligible.sort_by { |provider| [-scores[provider.name].total, tie_priority(provider), provider.name] }
      end

      def tie_priority(provider)
        provider.priority || LAST_PRIORITY
      end

      def enabled_goals
        GOALS.select { |goal| @policy.enabled?(goal::KEY) }
      end

      def detect_conflicts(scores)
        disagreements(scores) + unmet_conflicts
      end

      def disagreements(scores)
        winners = unique_winners(scores)
        winners.keys.combination(2).filter_map { |left, right| disagreement(left, right, winners) }
      end

      def disagreement(left, right, winners)
        return if winners[left] == winners[right]

        Conflict.new(
          kind: Reasons::GOAL_DISAGREEMENT,
          details: { "goal_a" => left, "preferred_a" => winners[left],
                     "goal_b" => right, "preferred_b" => winners[right] }
        )
      end

      def unique_winners(scores)
        enabled_goals.each_with_object({}) do |goal, winners|
          winner = unique_winner(goal, scores)
          winners[goal::KEY] = winner unless winner.nil?
        end
      end

      def unique_winner(goal, scores)
        ranked = ranked_scores(goal, scores)
        max = ranked.map(&:last).max
        tops = ranked.select { |_, score| score == max }
        return unless unique_preference?(tops, ranked, max)

        tops.first.first
      end

      def ranked_scores(goal, scores)
        @eligible.map { |provider| [provider.name, contribution_score(scores, provider, goal)] }
      end

      def unique_preference?(tops, ranked, max)
        return false if tops.size != 1
        return false if max.zero? && ranked.all? { |_, score| score.zero? }

        true
      end

      def contribution_score(scores, provider, goal)
        scores.fetch(provider.name).contribution(goal::KEY)&.score || 0.0
      end

      def unmet_conflicts
        names = @eligible.map(&:name)
        count = unmet_kind(@snapshot.unmet_count_targets(names), Reasons::UNMET_COUNT_SHARE)
        volume = unmet_kind(@snapshot.unmet_volume_targets(names), Reasons::UNMET_VOLUME_SHARE)
        count + volume
      end

      def unmet_kind(providers, kind)
        providers.map { |name| Conflict.new(kind: kind, provider: name) }
      end

      def unmet_notes
        unmet_conflicts.map { |conflict| "#{conflict.kind}: #{conflict.provider}" }
      end
    end
  end
end
