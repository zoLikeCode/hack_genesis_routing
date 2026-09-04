# frozen_string_literal: true

module Routing
  class DecisionExplainer
    FALLBACK_DETAILS = "provider selected as fallback after eligible external providers were exhausted"

    def self.details(selection:, policy:, result:)
      base = selection.fallback? ? FALLBACK_DETAILS : score_details(selection, policy)
      [base, outcome_details(result)].compact.join("; ")
    end

    def self.score_details(selection, policy)
      score_parts(selection, policy).join("; ")
    end
    private_class_method :score_details

    def self.score_parts(selection, policy)
      score = selection.ranking.scores.fetch(selection.provider.name)
      identity_parts(selection, policy, score) + metric_parts(score) +
        contributions(score, selection.provider.name, policy) +
        selection.ranking.notes + disagreement_notes(selection.ranking)
    end
    private_class_method :score_parts

    def self.identity_parts(selection, policy, score)
      profile = policy.profile_for(selection.provider.name) || "individual"
      [
        "profile=#{profile}",
        "total_score=#{score.total.round(4)}",
        "base_total=#{score.base_total.round(4)}",
        "health=#{score.health.round(4)}"
      ]
    end
    private_class_method :identity_parts

    def self.metric_parts(score)
      vector = score.metrics
      return [] if vector.nil?

      availability = (vector.availability * 100).round(1)
      acceptance = (vector.acceptance * 100).round(1)
      ["availability=#{availability}%", "acceptance=#{acceptance}%"]
    end
    private_class_method :metric_parts

    def self.outcome_details(result)
      return "timeout reservation retained pending status-check" if result == "expired"

      "reservation rolled back after explicit rejection" if result == "rejected"
    end
    private_class_method :outcome_details

    def self.contributions(score, provider_name, policy)
      score.contributions.map do |item|
        weight = policy.weight_for(item.name, provider: provider_name)
        "#{item.name}=#{item.score.round(3)}*#{weight}"
      end
    end
    private_class_method :contributions

    def self.disagreement_notes(ranking)
      ranking.conflicts.filter_map { |conflict| conflict_note(conflict) }
    end
    private_class_method :disagreement_notes

    def self.conflict_note(conflict)
      details = conflict.details
      case conflict.kind
      when SoftGoals::Reasons::GOAL_DISAGREEMENT
        "goal_disagreement #{details.fetch('goal_a')}=#{details.fetch('preferred_a')} " \
        "vs #{details.fetch('goal_b')}=#{details.fetch('preferred_b')}"
      when SoftGoals::Reasons::METRIC_DISAGREEMENT
        "metric_disagreement #{details.fetch('metric_a')}=#{details.fetch('preferred_a')} " \
        "vs #{details.fetch('metric_b')}=#{details.fetch('preferred_b')}"
      end
    end
    private_class_method :conflict_note
  end
end
