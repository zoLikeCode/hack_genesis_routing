# frozen_string_literal: true

module Routing
  module Metrics
    class Catalog
      Stats = Data.define(:sample_size, :approved, :rejected, :expired, :p90_latency_sec)

      def self.call(observations:, provider:, operation:, config: nil)
        new(observations, provider, operation, config).call
      end

      def self.summarize(observations:, provider:, config: nil)
        new(observations, provider, nil, config).summarize
      end

      def initialize(observations, provider, operation, config)
        Routing.assert(observations.is_a?(Array) && observations.all?(History::Observation),
                       "catalog requires observations")
        Routing.assert(provider.is_a?(Provider), "catalog requires Provider")
        Routing.assert(operation.nil? || operation.is_a?(Operation), "catalog requires Operation")
        @observations = observations
        @provider = provider
        @operation = operation
        @config = config.is_a?(Config) ? config : Config.parse(config || {})
      end

      def call
        relevant = ordered(relevant_observations)
        return live_prior if relevant.empty?

        overall = stats(relevant)
        segment, scope = select_segment(relevant)
        build_vector(stats(segment), overall, scope, stats(recent_slice(relevant)))
      end

      def summarize
        rows = ordered(@observations)
        return live_prior if rows.empty?

        overall = stats(rows)
        build_vector(overall, overall, "provider", stats(recent_slice(rows)))
      end

      private

      def build_vector(segment, overall, scope, recent)
        approval = smoothed_approval(segment)
        timeout = smoothed_timeout(segment)
        acceptance = smoothed_acceptance(segment)
        latency = latency_quality(segment)
        Vector.new(
          score: to_signed(blended_quality(segment, overall)),
          sample_size: segment.sample_size,
          scope: scope,
          approval_rate: approval,
          availability: 1.0 - timeout,
          acceptance: acceptance,
          latency: latency,
          health: health_factor(recent),
          timeout_rate: timeout,
          refusal_rate: refusal_rate(segment),
          p90_latency_sec: segment.p90_latency_sec
        )
      end

      def relevant_observations
        return @observations if @operation.nil?

        @observations.select do |observation|
          observation.provider_name == @provider.name &&
            precedes?(observation) && Metrics.compatible?(@provider, observation)
        end
      end

      def precedes?(observation)
        @operation.created_at.nil? || observation.created_at < @operation.created_at
      end

      def ordered(rows)
        rows.each_with_index.sort_by { |row, index| [row.created_at, index] }.map(&:first)
      end

      def recent_slice(rows)
        rows.last(@config.recent_observations)
      end

      def select_segment(observations)
        return [observations, "provider"] if @operation.nil?

        candidates = [
          [bank_amount_rows(observations), "bank_amount"],
          [observations.select { |row| row.bank == @operation.bank }, "bank"],
          [observations.select { |row| same_amount_band?(row.amount) }, "amount"]
        ]
        candidates.find { |rows, _scope| rows.size >= @config.segment_min_size } || [observations, "provider"]
      end

      def bank_amount_rows(observations)
        observations.select { |row| row.bank == @operation.bank && same_amount_band?(row.amount) }
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
          rejected: observations.count { |row| row.status == "rejected" },
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

        confidence = segment.sample_size / (segment.sample_size + @config.segment_confidence_strength)
        (confidence * segment_score) + ((1.0 - confidence) * quality_score(overall))
      end

      def quality_score(stats)
        weights = @config.normalized_component_weights
        return 0.0 if weights.empty?

        parts = {
          "approval_rate" => smoothed_approval(stats),
          "availability" => 1.0 - smoothed_timeout(stats),
          "acceptance" => smoothed_acceptance(stats),
          "latency" => latency_quality(stats)
        }
        weights.sum { |name, weight| weight * parts.fetch(name) }
      end

      def health_factor(stats)
        cfg = @config.health
        availability = 1.0 - smoothed_timeout(stats)
        acceptance = smoothed_acceptance(stats)
        blend = weighted_health(cfg, availability, acceptance)
        floor = cfg.fetch("floor")
        exponent = cfg.fetch("exponent")
        floor + ((1.0 - floor) * (blend**exponent))
      end

      def weighted_health(cfg, availability, acceptance)
        availability_weight = cfg.fetch("availability_weight").to_f
        acceptance_weight = cfg.fetch("acceptance_weight").to_f
        total = availability_weight + acceptance_weight
        return 1.0 if total.zero?

        ((availability_weight * availability) + (acceptance_weight * acceptance)) / total
      end

      def smoothed_approval(stats)
        numerator = stats.approved + (@config.prior_strength * live_conversion)
        numerator / (stats.sample_size + @config.prior_strength)
      end

      def smoothed_timeout(stats)
        numerator = stats.expired + (@config.timeout_prior_strength * @config.timeout_prior)
        numerator / (stats.sample_size + @config.timeout_prior_strength)
      end

      def smoothed_acceptance(stats)
        answered = stats.approved + stats.rejected
        numerator = stats.approved + (@config.prior_strength * live_conversion)
        numerator / (answered + @config.prior_strength)
      end

      def latency_quality(stats)
        (1.0 - (stats.p90_latency_sec / @config.bad_p90_sec)).clamp(0.0, 1.0)
      end

      def refusal_rate(stats)
        stats.sample_size.zero? ? 0.0 : stats.rejected.to_f / stats.sample_size
      end

      def to_signed(raw)
        ((2.0 * raw) - 1.0).clamp(-1.0, 1.0)
      end

      def live_prior
        synthetic = Stats.new(sample_size: 0, approved: 0, rejected: 0, expired: 0, p90_latency_sec: 0.0)
        timeout = @config.timeout_prior
        Vector.new(
          score: to_signed(quality_score(synthetic)),
          sample_size: 0,
          scope: "live_prior",
          approval_rate: live_conversion,
          availability: 1.0 - timeout,
          acceptance: live_conversion,
          latency: 1.0,
          health: health_factor(synthetic),
          timeout_rate: timeout,
          refusal_rate: 0.0,
          p90_latency_sec: nil
        )
      end

      def live_conversion
        @provider.conversion_24h.nil? ? 0.5 : @provider.conversion_24h.to_f
      end
    end
  end
end
