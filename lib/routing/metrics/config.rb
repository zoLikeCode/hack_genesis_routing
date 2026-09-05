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

      def lookback_seconds
        window.fetch("lookback_hours") * 60 * 60
      end

      def window
        @data.fetch("window")
      end

      def smoothing
        @data.fetch("smoothing")
      end

      def prior_strength
        smoothing.fetch("prior_strength")
      end

      def default_conversion_prior
        smoothing.fetch("default_conversion_prior")
      end

      def segment_min_size
        smoothing.fetch("segment_min_size")
      end

      def segment_prior_strength
        smoothing.fetch("segment_prior_strength")
      end
    end
  end
end
