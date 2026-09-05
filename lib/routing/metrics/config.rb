# frozen_string_literal: true

module Routing
  module Metrics
    class Config
      attr_reader :data

      def self.default
        parse({})
      end

      def self.parse(raw)
        ConfigValidator.input_error!("metrics must be a mapping") unless raw.respond_to?(:to_h)
        hash = ConfigValidator.stringify(raw.to_h)
        ConfigValidator.reject_unknown!(hash.keys, ConfigValidator::ROOT_KEYS, "metrics")
        merged = ConfigValidator.merge_hashes(ConfigValidator.default_hash, hash)
        new(ConfigValidator.validate!(merged))
      end

      def self.normalize_overlay(raw, context)
        ConfigValidator.input_error!("#{context} must be a mapping") unless raw.respond_to?(:to_h)
        hash = ConfigValidator.stringify(raw.to_h)
        ConfigValidator.reject_unknown!(hash.keys, ConfigValidator::ROOT_KEYS, context)
        ConfigValidator.validate_overlay!(hash, context)
        ConfigValidator.freeze_tree(hash)
      end

      def self.combine(base, overlay)
        Routing.assert(base.is_a?(Config), "metrics combine requires Config")
        return base if overlay.nil? || overlay.empty?

        base.overlay(overlay)
      end

      def initialize(data)
        Routing.assert(data.is_a?(Hash), "metrics config must be a Hash")
        @data = ConfigValidator.freeze_tree(data)
      end

      def overlay(partial)
        merged = ConfigValidator.merge_hashes(@data, ConfigValidator.stringify(partial))
        self.class.new(ConfigValidator.validate!(merged))
      end

      def max_observations
        window.fetch("max_observations")
      end

      def recent_observations
        window.fetch("recent_observations")
      end

      def combination
        @data.fetch("combination")
      end

      def window
        @data.fetch("window")
      end

      def smoothing
        @data.fetch("smoothing")
      end

      def components
        @data.fetch("components")
      end

      def health
        @data.fetch("multipliers").fetch("health")
      end

      def health_enabled?
        health.fetch("enabled")
      end

      def component_enabled?(name)
        entry = components[name]
        !entry.nil? && entry.fetch("enabled")
      end

      def normalized_component_weights
        enabled = components.select { |_name, entry| entry.fetch("enabled") }
        total = enabled.values.sum { |entry| entry.fetch("weight").to_f }
        return {} if total.zero?

        enabled.to_h { |name, entry| [name, entry.fetch("weight").to_f / total] }
      end

      def bad_p90_sec
        components.fetch("latency").fetch("bad_p90_sec")
      end

      def prior_strength
        smoothing.fetch("prior_strength")
      end

      def approval_prior
        smoothing.fetch("approval_prior")
      end

      def timeout_prior
        smoothing.fetch("timeout_prior")
      end

      def timeout_prior_strength
        smoothing.fetch("timeout_prior_strength")
      end

      def segment_min_size
        smoothing.fetch("segment_min_size")
      end

      def segment_confidence_strength
        smoothing.fetch("segment_confidence_strength")
      end
    end
  end
end
