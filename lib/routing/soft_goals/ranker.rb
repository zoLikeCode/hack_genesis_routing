# frozen_string_literal: true

module Routing
  module SoftGoals
    class Ranker
      LAST_PRIORITY = 100
      METRIC_KEYS = Metrics::COMPONENTS

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
          notes: unmet_notes + metric_notes(scores)
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
        contributions = enabled_goals(provider).map do |goal|
          goal.call(provider, @operation, @snapshot, @policy)
        end
        base = weighted_total(provider, contributions)
        vector = metric_vector(provider)
        health = applied_health(provider, vector)
        Score.new(
          total: base * health, base_total: base, health: health,
          contributions: contributions, reason: reason, metrics: vector
        )
      end

      def weighted_total(provider, contributions)
        contributions.sum { |item| @policy.weight_for(item.name, provider: provider.name) * item.score }
      end

      def metric_vector(provider)
        observations = metric_observations(provider)
        return if observations.nil?

        Metrics::Catalog.call(
          observations: observations,
          provider: provider,
          operation: @operation,
          config: @policy.metrics_for(provider)
        )
      end

      def metric_observations(provider)
        return @snapshot.metrics.observations_for(provider.name) unless @snapshot.metrics.nil?
        return @snapshot.history.observations_for(provider.name) unless @snapshot.history.nil?

        nil
      end

      def applied_health(provider, vector)
        return 1.0 if vector.nil?
        return 1.0 unless @policy.metrics_for(provider).health_enabled?

        vector.health
      end

      def sort_eligible(scores)
        @eligible.sort_by { |provider| [-scores[provider.name].total, tie_priority(provider), provider.name] }
      end

      def tie_priority(provider)
        provider.priority || LAST_PRIORITY
      end

      def enabled_goals(provider = nil)
        return GOALS.select { |goal| @policy.enabled?(goal::KEY, provider: provider.name) } unless provider.nil?

        GOALS.select do |goal|
          @eligible.any? { |candidate| @policy.enabled?(goal::KEY, provider: candidate.name) }
        end
      end

      def detect_conflicts(scores)
        disagreements(scores) + metric_disagreements(scores) + unmet_conflicts
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
        return if ranked.empty?

        pick_unique(ranked)
      end

      def ranked_scores(goal, scores)
        @eligible.filter_map do |provider|
          next unless @policy.enabled?(goal::KEY, provider: provider.name)

          [provider.name, contribution_score(scores, provider, goal)]
        end
      end

      def unique_preference?(tops, ranked, max)
        return false if tops.size != 1
        return false if max.zero? && ranked.all? { |_, score| score.zero? }

        true
      end

      def pick_unique(ranked)
        max = ranked.map(&:last).max
        tops = ranked.select { |_, score| score == max }
        return unless unique_preference?(tops, ranked, max)

        tops.first.first
      end

      def contribution_score(scores, provider, goal)
        scores.fetch(provider.name).contribution(goal::KEY)&.score || 0.0
      end

      def metric_disagreements(scores)
        winners = unique_metric_winners(scores)
        winners.keys.combination(2).filter_map { |left, right| metric_disagreement(left, right, winners) }
      end

      def metric_disagreement(left, right, winners)
        return if winners[left] == winners[right]

        Conflict.new(
          kind: Reasons::METRIC_DISAGREEMENT,
          details: { "metric_a" => left, "preferred_a" => winners[left],
                     "metric_b" => right, "preferred_b" => winners[right] }
        )
      end

      def unique_metric_winners(scores)
        METRIC_KEYS.each_with_object({}) do |key, winners|
          ranked = metric_ranked(scores, key)
          winner = pick_unique(ranked)
          winners[key] = winner unless winner.nil?
        end
      end

      def metric_ranked(scores, key)
        @eligible.filter_map do |provider|
          vector = scores.fetch(provider.name).metrics
          next if vector.nil?

          [provider.name, vector.public_send(key)]
        end
      end

      def metric_notes(scores)
        metric_disagreements(scores).map do |conflict|
          details = conflict.details
          "#{conflict.kind}: #{details.fetch('metric_a')}=#{details.fetch('preferred_a')} " \
            "vs #{details.fetch('metric_b')}=#{details.fetch('preferred_b')}"
        end
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
