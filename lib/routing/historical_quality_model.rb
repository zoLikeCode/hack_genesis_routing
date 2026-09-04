# frozen_string_literal: true

module Routing
  class HistoricalQualityModel
    Stats = Data.define(:sample_size, :approved, :expired, :p90_latency_sec)

    SEGMENT_MIN_SIZE = 5
    PRIOR_STRENGTH = 10.0
    TIMEOUT_PRIOR = 0.10
    TIMEOUT_PRIOR_STRENGTH = 5.0
    SEGMENT_CONFIDENCE_STRENGTH = 10.0
    BAD_P90_LATENCY_SEC = 600.0
    APPROVAL_WEIGHT = 0.60
    TIMEOUT_WEIGHT = 0.25
    LATENCY_WEIGHT = 0.15

    def self.call(observations:, provider:, operation:)
      new(observations, provider, operation).call
    end

    def initialize(observations, provider, operation)
      Routing.assert(observations.is_a?(Array) && observations.all?(History::Observation),
                     "historical quality requires observations")
      Routing.assert(provider.is_a?(Provider), "historical quality requires Provider")
      Routing.assert(operation.is_a?(Operation), "historical quality requires Operation")
      @observations = observations
      @provider = provider
      @operation = operation
    end

    def call
      relevant = relevant_observations
      return live_prior if relevant.empty?

      overall = stats(relevant)
      segment, scope = select_segment(relevant)
      segment_stats = stats(segment)
      build_quality(segment_stats, overall, scope)
    end

    private

    def build_quality(segment, overall, scope)
      raw = blended_quality(segment, overall)
      History::Quality.new(
        score: ((2.0 * raw) - 1.0).clamp(-1.0, 1.0),
        sample_size: segment.sample_size,
        scope: scope,
        approval_rate: smoothed_approval(segment),
        timeout_rate: smoothed_timeout(segment),
        p90_latency_sec: segment.p90_latency_sec
      )
    end

    def relevant_observations
      @observations.select do |observation|
        observation.provider_name == @provider.name &&
          precedes?(observation) && compatible_with_current_rules?(observation)
      end
    end

    def precedes?(observation)
      @operation.created_at.nil? || observation.created_at < @operation.created_at
    end

    def compatible_with_current_rules?(observation)
      amount_compatible?(observation.amount) && bank_compatible?(observation.bank)
    end

    def amount_compatible?(amount)
      return false if !@provider.limit_amount_min.nil? && amount < @provider.limit_amount_min
      return false if !@provider.limit_amount_max.nil? && amount > @provider.limit_amount_max

      true
    end

    def bank_compatible?(bank)
      return true if @provider.banks.empty?

      included = @provider.banks.include?(bank)
      @provider.exclude_banks ? !included : included
    end

    def select_segment(observations)
      candidates = [
        [observations.select { |row| row.bank == @operation.bank && same_amount_band?(row.amount) }, "bank_amount"],
        [observations.select { |row| row.bank == @operation.bank }, "bank"],
        [observations.select { |row| same_amount_band?(row.amount) }, "amount"]
      ]
      candidates.find { |rows, _scope| rows.size >= SEGMENT_MIN_SIZE } || [observations, "provider"]
    end

    def same_amount_band?(amount)
      amount_band(amount) == amount_band(@operation.amount)
    end

    def amount_band(amount)
      return "up_to_5k" if amount <= 5_000
      return "5k_to_15k" if amount <= 15_000
      return "15k_to_50k" if amount <= 50_000
      return "50k_to_100k" if amount <= 100_000

      "above_100k"
    end

    def stats(observations)
      Stats.new(
        sample_size: observations.size,
        approved: observations.count { |row| row.status == "approved" },
        expired: observations.count { |row| row.status == "expired" },
        p90_latency_sec: percentile(observations.map(&:latency_sec), 0.90)
      )
    end

    def percentile(values, percentile)
      sorted = values.sort
      return 0.0 if sorted.empty?

      rank = (sorted.size - 1) * percentile
      lower = sorted.fetch(rank.floor)
      upper = sorted.fetch(rank.ceil)
      lower + ((upper - lower) * (rank - rank.floor))
    end

    def blended_quality(segment, overall)
      segment_score = quality_score(segment)
      return segment_score if segment.sample_size == overall.sample_size

      confidence = segment.sample_size / (segment.sample_size + SEGMENT_CONFIDENCE_STRENGTH)
      (confidence * segment_score) + ((1.0 - confidence) * quality_score(overall))
    end

    def quality_score(stats)
      approval = smoothed_approval(stats)
      timeout_safety = 1.0 - smoothed_timeout(stats)
      latency = (1.0 - (stats.p90_latency_sec / BAD_P90_LATENCY_SEC)).clamp(0.0, 1.0)
      (APPROVAL_WEIGHT * approval) + (TIMEOUT_WEIGHT * timeout_safety) + (LATENCY_WEIGHT * latency)
    end

    def smoothed_approval(stats)
      (stats.approved + (PRIOR_STRENGTH * live_conversion)) / (stats.sample_size + PRIOR_STRENGTH)
    end

    def smoothed_timeout(stats)
      numerator = stats.expired + (TIMEOUT_PRIOR_STRENGTH * TIMEOUT_PRIOR)
      numerator / (stats.sample_size + TIMEOUT_PRIOR_STRENGTH)
    end

    def live_prior
      raw = (APPROVAL_WEIGHT * live_conversion) + (TIMEOUT_WEIGHT * (1.0 - TIMEOUT_PRIOR)) + LATENCY_WEIGHT
      History::Quality.new(
        score: ((2.0 * raw) - 1.0).clamp(-1.0, 1.0),
        sample_size: 0,
        scope: "live_prior",
        approval_rate: live_conversion,
        timeout_rate: TIMEOUT_PRIOR,
        p90_latency_sec: nil
      )
    end

    def live_conversion
      @provider.conversion_24h.nil? ? 0.5 : @provider.conversion_24h.to_f
    end
  end
end
