# frozen_string_literal: true

module Routing
  module Metrics
    Vector = Data.define(
      :score, :sample_size, :scope, :source, :prior,
      :initial_approved_count, :initial_rejected_count, :initial_timeout_count,
      :initial_approval_rate, :initial_timeout_rate, :initial_refusal_rate, :initial_acceptance,
      :final_approved_count, :final_rejected_count, :unresolved_count,
      :p90_initial_latency_sec, :latency_sample_size, :last_observation_at, :data_age_sec
    )

    def self.compatible?(provider, observation)
      Routing.assert(provider.is_a?(Provider), "compatibility requires Provider")
      Routing.assert(observation.is_a?(History::Observation), "compatibility requires Observation")
      amount_compatible?(provider, observation.amount) && bank_compatible?(provider, observation.bank)
    end

    def self.amount_compatible?(provider, amount)
      return false if !provider.limit_amount_min.nil? && amount < provider.limit_amount_min
      return false if !provider.limit_amount_max.nil? && amount > provider.limit_amount_max

      true
    end

    def self.bank_compatible?(provider, bank)
      return true if provider.banks.empty?

      included = provider.banks.include?(bank)
      provider.exclude_banks ? !included : included
    end
  end
end
