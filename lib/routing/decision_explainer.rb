# frozen_string_literal: true

module Routing
  class DecisionExplainer
    FALLBACK_DETAILS = "provider selected as fallback after eligible external providers were exhausted"

    def self.details(selection:, policy:, result:)
      base = selection.fallback? ? FALLBACK_DETAILS : score_details(selection, policy)
      [base, outcome_details(result)].compact.join("; ")
    end

    def self.score_details(selection, policy)
      score = selection.ranking.scores.fetch(selection.provider.name)
      profile = policy.profile_for(selection.provider.name) || "individual"
      parts = ["profile=#{profile}", "total_score=#{score.total.round(4)}"]
      (parts + contributions(score, selection.provider.name, policy) + selection.ranking.notes).join("; ")
    end
    private_class_method :score_details

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
  end
end
