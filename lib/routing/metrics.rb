# frozen_string_literal: true

module Routing
  module Metrics
    # A metric is an observable. Strategies combine metrics into a score.
    # COMPONENTS are the window-quality family; Inputs lists every family.
    # Ranker consumes the window vector twice: SoftGoals::HistoricalQuality
    # (signed blend of COMPONENTS) and health (multiplier on the strategy mix).
    COMPONENTS = %w[approval_rate availability acceptance latency].freeze
    COMBINATIONS = %w[weighted_sum].freeze
    MULTIPLIERS = %w[health].freeze

    Vector = Data.define(
      :score, :sample_size, :scope, :approval_rate, :availability, :acceptance, :latency,
      :health, :timeout_rate, :refusal_rate, :p90_latency_sec
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
