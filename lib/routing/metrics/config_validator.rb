# frozen_string_literal: true

module Routing
  module Metrics
    class ConfigValidator
      ROOT_KEYS = %w[window smoothing].freeze
      WINDOW_KEYS = %w[max_observations lookback_hours].freeze
      SMOOTHING_KEYS = %w[
        prior_strength default_conversion_prior segment_min_size segment_prior_strength
      ].freeze

      def self.validate!(hash)
        validate_window!(hash.fetch("window"))
        validate_smoothing!(hash.fetch("smoothing"))
        hash
      end

      def self.validate_overlay!(hash, _context)
        validate_window!(hash["window"], required: false) if hash.key?("window")
        validate_smoothing!(hash["smoothing"], required: false) if hash.key?("smoothing")
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
        validate_positive_number!(window["lookback_hours"], "metrics.window.lookback_hours", required: required)
      end
      private_class_method :validate_window!

      def self.validate_smoothing!(raw, required: true)
        mapping!("smoothing", raw)
        reject_unknown!(stringify(raw).keys, SMOOTHING_KEYS, "metrics.smoothing")
        data = stringify(raw)
        validate_non_negative_number!(data["prior_strength"], "metrics.smoothing.prior_strength", required: required)
        validate_unit_interval!(
          data["default_conversion_prior"], "metrics.smoothing.default_conversion_prior", required: required
        )
        validate_positive_int!(data["segment_min_size"], "metrics.smoothing.segment_min_size", required: required)
        validate_non_negative_number!(
          data["segment_prior_strength"], "metrics.smoothing.segment_prior_strength", required: required
        )
      end
      private_class_method :validate_smoothing!

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

      def self.validate_positive_number!(value, field, required: true)
        return if value.nil? && !required
        return if value.is_a?(Numeric) && value.positive?

        input_error!("#{field} must be a positive number")
      end
      private_class_method :validate_positive_number!

      def self.validate_unit_interval!(value, field, required: true)
        return if value.nil? && !required
        return if value.is_a?(Numeric) && value.between?(0, 1)

        input_error!("#{field} must be in [0, 1]")
      end
      private_class_method :validate_unit_interval!

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
