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
          ordered: sort_eligible(scores), scores: scores,
          conflicts: disagreements(scores) + unmet_conflicts,
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
        vector = metric_vector(provider)
        contributions = enabled_goals(provider).map { |goal| contribute(goal, provider, vector) }
        total = contributions.sum do |item|
          @policy.weight_for(item.name, provider: provider.name) * item.score
        end
        Score.new(total: total.clamp(0.0, 1.0), contributions: contributions, reason: reason, metrics: vector)
      end

      def contribute(goal, provider, vector)
        case goal::KEY
        when Conversion::KEY
          Conversion.from_vector(vector)
        when CountShare::KEY
          CountShare.from_result(count_share_results.fetch(provider.name))
        when VolumeShare::KEY
          VolumeShare.from_result(volume_share_results.fetch(provider.name))
        when CascadePriority::KEY
          CascadePriority.from_score(provider, cascade_scores.fetch(provider.name))
        else
          goal.call(provider, @operation, @snapshot, @policy)
        end
      end

      def count_share_results
        @count_share_results ||= CountShare.score_all(candidates: @eligible, snapshot: @snapshot)
      end

      def volume_share_results
        @volume_share_results ||= VolumeShare.score_all(
          candidates: @eligible, operation: @operation, snapshot: @snapshot
        )
      end

      def cascade_scores
        @cascade_scores ||= CascadePriority.score_all(providers: external_pool)
      end

      def external_pool
        all = @snapshot.providers
        all = @eligible if all.empty?
        all.select { |provider| provider.primary?(fallback: @policy.fallback_provider) }
      end

      def metric_vector(provider)
        Metrics::Catalog.call(
          observations: metric_observations(provider), provider: provider,
          operation: @operation, config: @policy.metrics_for(provider)
        )
      end

      def metric_observations(provider)
        return @snapshot.metrics.observations_for(provider.name) unless @snapshot.metrics.nil?
        return @snapshot.history.observations_for(provider.name) unless @snapshot.history.nil?

        []
      end

      def sort_eligible(scores)
        @eligible.sort_by { |provider| [-scores.fetch(provider.name).total, tie_priority(provider), provider.name] }
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

      def disagreements(scores)
        winners = unique_winners(scores)
        winners.keys.combination(2).filter_map do |left, right|
          next if winners[left] == winners[right]

          Conflict.new(
            kind: Reasons::GOAL_DISAGREEMENT,
            details: { "goal_a" => left, "preferred_a" => winners[left],
                       "goal_b" => right, "preferred_b" => winners[right] }
          )
        end
      end

      def unique_winners(scores)
        enabled_goals.each_with_object({}) do |goal, winners|
          ranked = ranking_for_goal(goal, scores)
          next if ranked.empty?

          winner = unique_winner(ranked)
          winners[goal::KEY] = winner unless winner.nil?
        end
      end

      def ranking_for_goal(goal, scores)
        @eligible.filter_map do |provider|
          next unless @policy.enabled?(goal::KEY, provider: provider.name)

          contribution = scores.fetch(provider.name).contribution(goal::KEY)
          [provider.name, contribution&.score || 0.0]
        end
      end

      def unique_winner(ranked)
        maximum = ranked.map(&:last).max
        return if maximum.zero? && ranked.all? { |_name, score| score.zero? }

        top = ranked.select { |_name, score| score == maximum }
        top.first.first if top.one?
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
