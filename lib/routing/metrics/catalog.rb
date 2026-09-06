# frozen_string_literal: true

module Routing
  module Metrics
    # Produces the conversion estimate used by routing and the accompanying
    # initial/final diagnostics. Only immutable initial_status affects score.
    class Catalog
      Stats = Data.define(
        :sample_size, :initial_approved, :initial_rejected, :initial_expired,
        :final_approved, :final_rejected, :unresolved, :p90_latency_sec, :latency_sample_size
      )
      ANSWERED = %w[approved rejected].freeze

      def self.call(observations:, provider:, operation:, config: nil)
        new(observations, provider, operation, config).call
      end

      def self.summarize(observations:, provider:, config: nil, as_of: nil)
        new(observations, provider, nil, config, as_of: as_of).summarize
      end

      def initialize(observations, provider, operation, config, as_of: nil)
        Routing.assert(observations.is_a?(Array) && observations.all?(History::Observation),
                       "catalog requires observations")
        Routing.assert(provider.is_a?(Provider), "catalog requires Provider")
        Routing.assert(operation.nil? || operation.is_a?(Operation), "catalog requires Operation")
        Routing.assert(as_of.nil? || as_of.is_a?(Time), "catalog as_of must be Time")
        @observations = observations
        @provider = provider
        @operation = operation
        @as_of = as_of
        @config = config.is_a?(Config) ? config : Config.parse(config || {})
      end

      def call
        rows = scoring_window(relevant_observations, reference_time)
        return prior_vector if rows.empty?

        segment, scope = select_segment(rows)
        estimate = segment_estimate(segment, rows, scope)
        build_vector(segment, scope, estimate, source_for(scope), reference_time)
      end

      def summarize
        reference = @as_of || latest_time(@observations)
        rows = scoring_window(compatible_observations(@observations), reference)
        return prior_vector if rows.empty?

        build_vector(rows, "provider", posterior(stats(rows), prior), "provider_history", reference)
      end

      private

      def relevant_observations
        @observations.select do |observation|
          observation.provider_name == @provider.name &&
            precedes?(observation) && Metrics.compatible?(@provider, observation)
        end
      end

      def compatible_observations(rows)
        rows.select do |row|
          row.provider_name == @provider.name && Metrics.compatible?(@provider, row)
        end
      end

      def precedes?(observation)
        return false if observation.operation_id == @operation.id
        return true if @operation.created_at.nil?

        observation.created_at <= @operation.created_at
      end

      def scoring_window(rows, reference)
        filtered = if reference.nil?
                     rows
                   else
                     cutoff = reference - @config.lookback_seconds
                     rows.select { |row| row.created_at.between?(cutoff, reference) }
                   end
        ordered(filtered).last(@config.max_observations)
      end

      def ordered(rows)
        rows.each_with_index.sort_by { |row, index| attempt_key(row, index) }.map(&:first)
      end

      def attempt_key(row, index)
        sequence = row.admission_sequence
        return [1, sequence, index] unless sequence.nil?

        [0, row.attempted_at.to_f, index]
      end

      def reference_time
        @operation&.created_at
      end

      def latest_time(rows)
        rows.map(&:created_at).max
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

      def segment_estimate(segment, overall, scope)
        return posterior(stats(overall), prior) if scope == "provider"

        rest_estimate = estimate_for_segment_remainder(segment, overall)
        segment_stats = stats(segment)
        strength = @config.segment_prior_strength
        return rest_estimate if segment_stats.sample_size.zero? && strength.zero?

        (segment_stats.initial_approved + (strength * rest_estimate)) / (segment_stats.sample_size + strength)
      end

      def estimate_for_segment_remainder(segment, overall)
        selected_ids = segment.to_h { |row| [row.operation_id, true] }
        remainder = overall.reject { |row| selected_ids.key?(row.operation_id) }
        remainder.empty? ? prior : posterior(stats(remainder), prior)
      end

      def posterior(row_stats, prior_value)
        strength = @config.prior_strength
        return prior_value if row_stats.sample_size.zero? && strength.zero?

        (row_stats.initial_approved + (strength * prior_value)) / (row_stats.sample_size + strength)
      end

      def prior
        value = @provider.conversion_24h
        value = @config.default_conversion_prior if value.nil?
        value.to_f.clamp(0.0, 1.0)
      end

      def stats(observations)
        latencies = initial_answer_latencies(observations)
        initial = observations.map(&:initial_status).tally
        final = observations.map(&:status).tally
        Stats.new(
          sample_size: observations.size,
          initial_approved: initial.fetch("approved", 0),
          initial_rejected: initial.fetch("rejected", 0),
          initial_expired: initial.fetch("expired", 0),
          final_approved: final.fetch("approved", 0),
          final_rejected: final.fetch("rejected", 0),
          unresolved: final.fetch("expired", 0),
          p90_latency_sec: latencies.empty? ? nil : percentile(latencies, 0.90),
          latency_sample_size: latencies.size
        )
      end

      def initial_answer_latencies(observations)
        observations.filter_map do |row|
          next unless ANSWERED.include?(row.initial_status)

          row.latency_sec
        end
      end

      def percentile(values, percentile)
        sorted = values.sort
        rank = (sorted.size - 1) * percentile
        lower = sorted.fetch(rank.floor)
        upper = sorted.fetch(rank.ceil)
        lower + ((upper - lower) * (rank - rank.floor))
      end

      def build_vector(rows, scope, estimate, source, reference)
        row_stats = stats(rows)
        answered = row_stats.initial_approved + row_stats.initial_rejected
        last = latest_time(rows)
        Vector.new(
          **vector_attributes(row_stats, answered),
          score: estimate.clamp(0.0, 1.0), sample_size: row_stats.sample_size,
          scope: scope, source: source, prior: prior,
          p90_initial_latency_sec: row_stats.p90_latency_sec,
          latency_sample_size: row_stats.latency_sample_size,
          last_observation_at: last,
          data_age_sec: reference.nil? || last.nil? ? nil : [reference - last, 0].max
        )
      end

      def vector_attributes(row_stats, answered)
        {
          initial_approved_count: row_stats.initial_approved,
          initial_rejected_count: row_stats.initial_rejected,
          initial_timeout_count: row_stats.initial_expired,
          initial_approval_rate: rate(row_stats.initial_approved, row_stats.sample_size),
          initial_timeout_rate: rate(row_stats.initial_expired, row_stats.sample_size),
          initial_refusal_rate: rate(row_stats.initial_rejected, row_stats.sample_size),
          initial_acceptance: rate(row_stats.initial_approved, answered),
          final_approved_count: row_stats.final_approved,
          final_rejected_count: row_stats.final_rejected,
          unresolved_count: row_stats.unresolved
        }
      end

      def prior_vector
        Vector.new(
          score: prior, sample_size: 0, scope: "prior", source: "published_prior", prior: prior,
          initial_approved_count: 0, initial_rejected_count: 0, initial_timeout_count: 0,
          initial_approval_rate: nil, initial_timeout_rate: nil, initial_refusal_rate: nil,
          initial_acceptance: nil, final_approved_count: 0, final_rejected_count: 0,
          unresolved_count: 0, p90_initial_latency_sec: nil, latency_sample_size: 0,
          last_observation_at: nil, data_age_sec: nil
        )
      end

      def source_for(scope)
        scope == "provider" ? "provider_history" : "segmented_history"
      end

      def rate(part, total)
        return if total.zero?

        part.to_f / total
      end
    end
  end
end
