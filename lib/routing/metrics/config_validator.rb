# frozen_string_literal: true

module Routing
  module Metrics
    class ConfigValidator
      ROOT_KEYS = %w[window smoothing combination components multipliers].freeze
      WINDOW_KEYS = %w[max_observations recent_observations].freeze
      SMOOTHING_KEYS = %w[
        prior_strength timeout_prior timeout_prior_strength segment_min_size segment_confidence_strength
      ].freeze
      COMPONENT_KEYS = %w[enabled weight bad_p90_sec].freeze
      HEALTH_KEYS = %w[enabled floor exponent availability_weight acceptance_weight].freeze

      def self.validate!(hash)
        validate_window!(hash.fetch("window"))
        validate_smoothing!(hash.fetch("smoothing"))
        validate_combination!(hash.fetch("combination"))
        validate_components!(hash.fetch("components"), "metrics.components")
        validate_multipliers!(hash.fetch("multipliers"))
        hash
      end

      def self.validate_overlay!(hash, context)
        validate_window!(hash["window"], required: false) if hash.key?("window")
        validate_smoothing!(hash["smoothing"], required: false) if hash.key?("smoothing")
        validate_combination!(hash["combination"]) if hash.key?("combination")
        validate_components!(hash["components"], "#{context}.components", required: false) if hash.key?("components")
        validate_multipliers!(hash["multipliers"], required: false) if hash.key?("multipliers")
      end

      def self.default_hash
        ConfigDefaults::HASH
      end

      def self.reject_unknown!(keys, allowed, context)
        unknown = keys - allowed
        return if unknown.empty?

        input_error!("#{context} has unknown keys: #{unknown.join(', ')}")
      end

      def self.input_error!(message)
        raise InvalidInputError, message
      end

      def self.stringify(hash)
        hash.to_h.transform_keys(&:to_s)
      end

      def self.freeze_tree(value)
        case value
        when Hash
          value.to_h { |key, item| [key.to_s, freeze_tree(item)] }.freeze
        when Array
          value.map { |item| freeze_tree(item) }.freeze
        else
          value
        end
      end

      def self.merge_hashes(base, overlay)
        stringify(base).merge(stringify(overlay)) do |_key, left, right|
          left.is_a?(Hash) && right.respond_to?(:to_h) ? merge_hashes(left, right.to_h) : right
        end
      end

      def self.validate_window!(raw, required: true)
        mapping!("window", raw)
        reject_unknown!(stringify(raw).keys, WINDOW_KEYS, "metrics.window")
        window = stringify(raw)
        validate_positive_int!(window["max_observations"], "metrics.window.max_observations", required: required)
        validate_positive_int!(window["recent_observations"], "metrics.window.recent_observations", required: required)
        return if window["max_observations"].nil? || window["recent_observations"].nil?
        return if window["recent_observations"] <= window["max_observations"]

        input_error!("metrics.window.recent_observations must be <= max_observations")
      end
      private_class_method :validate_window!

      def self.validate_smoothing!(raw, required: true)
        mapping!("smoothing", raw)
        reject_unknown!(stringify(raw).keys, SMOOTHING_KEYS, "metrics.smoothing")
        stringify(raw).each do |key, value|
          validate_non_negative_number!(value, "metrics.smoothing.#{key}", required: required)
        end
      end
      private_class_method :validate_smoothing!

      def self.validate_combination!(value)
        return if COMBINATIONS.include?(value)

        input_error!("metrics.combination must be one of: #{COMBINATIONS.join(', ')}")
      end
      private_class_method :validate_combination!

      def self.validate_components!(raw, context, required: true)
        mapping!("components", raw)
        stringify(raw).each do |name, entry|
          input_error!("#{context}.#{name} is not a registered metric") unless COMPONENTS.include?(name)
          mapping!(name, entry, context: context)
          validate_component!(stringify(entry), "#{context}.#{name}", required: required)
        end
      end
      private_class_method :validate_components!

      def self.validate_component!(entry, context, required:)
        reject_unknown!(entry.keys, COMPONENT_KEYS, context)
        validate_boolean!(entry["enabled"], "#{context}.enabled", required: required)
        validate_non_negative_number!(entry["weight"], "#{context}.weight", required: required)
        return unless entry.key?("bad_p90_sec")

        validate_positive_number!(entry["bad_p90_sec"], "#{context}.bad_p90_sec")
      end
      private_class_method :validate_component!

      def self.validate_multipliers!(raw, required: true)
        mapping!("multipliers", raw)
        stringify(raw).each do |name, entry|
          input_error!("metrics.multipliers.#{name} is not a registered multiplier") unless MULTIPLIERS.include?(name)
          mapping!(name, entry, context: "metrics.multipliers")
          validate_health!(stringify(entry), required: required)
        end
      end
      private_class_method :validate_multipliers!

      def self.validate_health!(entry, required:)
        reject_unknown!(entry.keys, HEALTH_KEYS, "metrics.multipliers.health")
        validate_boolean!(entry["enabled"], "metrics.multipliers.health.enabled", required: required)
        validate_floor!(entry["floor"], required: required)
        validate_non_negative_number!(entry["exponent"], "metrics.multipliers.health.exponent", required: required)
        validate_health_weight_fields!(entry, required)
        validate_health_weights!(entry)
      end
      private_class_method :validate_health!

      def self.validate_health_weight_fields!(entry, required)
        validate_non_negative_number!(
          entry["availability_weight"], "metrics.multipliers.health.availability_weight", required: required
        )
        validate_non_negative_number!(
          entry["acceptance_weight"], "metrics.multipliers.health.acceptance_weight", required: required
        )
      end
      private_class_method :validate_health_weight_fields!

      def self.validate_health_weights!(entry)
        availability = entry["availability_weight"]
        acceptance = entry["acceptance_weight"]
        return if availability.nil? || acceptance.nil?
        return if availability.positive? || acceptance.positive?

        input_error!("metrics.multipliers.health must have a positive availability or acceptance weight")
      end
      private_class_method :validate_health_weights!

      def self.validate_floor!(value, required:)
        return if value.nil? && !required
        return if value.is_a?(Numeric) && value.positive? && value <= 1.0

        input_error!("metrics.multipliers.health.floor must be in (0, 1]")
      end
      private_class_method :validate_floor!

      def self.validate_positive_int!(value, field, required:)
        return if value.nil? && !required
        return if value.is_a?(Integer) && value.positive?

        input_error!("#{field} must be a positive integer")
      end
      private_class_method :validate_positive_int!

      def self.validate_non_negative_number!(value, field, required: true)
        return if value.nil? && !required
        return if value.is_a?(Numeric) && value >= 0

        input_error!("#{field} must be a non-negative number")
      end
      private_class_method :validate_non_negative_number!

      def self.validate_positive_number!(value, field)
        return if value.is_a?(Numeric) && value.positive?

        input_error!("#{field} must be a positive number")
      end
      private_class_method :validate_positive_number!

      def self.validate_boolean!(value, field, required:)
        return if value.nil? && !required
        return if [true, false].include?(value)

        input_error!("#{field} must be true or false")
      end
      private_class_method :validate_boolean!

      def self.mapping!(name, raw, context: "metrics")
        return if raw.respond_to?(:to_h)

        input_error!("#{context}.#{name} must be a mapping")
      end
      private_class_method :mapping!
    end
  end
end
