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
        "total_score=#{score.total.round(4)}"
      ]
    end
    private_class_method :identity_parts

    def self.metric_parts(score)
      vector = score.metrics
      return [] if vector.nil?

      parts = [
        "conversion_estimate=#{vector.score.round(4)}",
        "conversion_source=#{vector.source}",
        "conversion_scope=#{vector.scope}",
        "conversion_n=#{vector.sample_size}",
        "conversion_prior=#{vector.prior.round(4)}"
      ]
      parts << "conversion_data_age_sec=#{vector.data_age_sec.round(1)}" unless vector.data_age_sec.nil?
      parts
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
        "#{item.name}=#{item.score.round(3)}*#{weight.round(4)}"
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
      end
    end
    private_class_method :conflict_note
  end
end
