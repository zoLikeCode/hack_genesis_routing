# frozen_string_literal: true

module Routing
  module Metrics
    module CatalogMath
      private

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
        combine(parts, weights)
      end

      def combine(parts, weights)
        case @config.combination
        when "weighted_sum"
          weights.sum { |name, weight| weight * parts.fetch(name) }
        else
          Routing.assert(false, "unsupported metrics combination #{@config.combination}")
        end
      end

      def health_factor(stats)
        cfg = @config.health
        availability = 1.0 - smoothed_timeout(stats)
        blend = health_blend(stats, cfg, availability)
        floor = cfg.fetch("floor")
        exponent = cfg.fetch("exponent")
        floor + ((1.0 - floor) * (blend**exponent))
      end

      def health_blend(stats, cfg, availability)
        return availability if (stats.approved + stats.rejected).zero?

        weighted_health(cfg, availability, smoothed_acceptance(stats))
      end

      def weighted_health(cfg, availability, acceptance)
        availability_weight = cfg.fetch("availability_weight").to_f
        acceptance_weight = cfg.fetch("acceptance_weight").to_f
        total = availability_weight + acceptance_weight
        return 1.0 if total.zero?

        ((availability_weight * availability) + (acceptance_weight * acceptance)) / total
      end

      def smoothed_approval(stats)
        numerator = stats.approved + (@config.prior_strength * @config.approval_prior)
        numerator / (stats.sample_size + @config.prior_strength)
      end

      def smoothed_timeout(stats)
        numerator = stats.expired + (@config.timeout_prior_strength * @config.timeout_prior)
        numerator / (stats.sample_size + @config.timeout_prior_strength)
      end

      def smoothed_acceptance(stats)
        answered = stats.approved + stats.rejected
        numerator = stats.approved + (@config.prior_strength * @config.approval_prior)
        numerator / (answered + @config.prior_strength)
      end

      def latency_quality(stats)
        return 1.0 if stats.p90_latency_sec.nil?

        (1.0 - (stats.p90_latency_sec / @config.bad_p90_sec)).clamp(0.0, 1.0)
      end

      def refusal_rate(stats)
        stats.sample_size.zero? ? 0.0 : stats.rejected.to_f / stats.sample_size
      end

      def to_signed(raw)
        ((2.0 * raw) - 1.0).clamp(-1.0, 1.0)
      end
    end
  end
end
