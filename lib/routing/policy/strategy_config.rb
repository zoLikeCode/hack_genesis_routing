# frozen_string_literal: true

module Routing
  class Policy
    class StrategyConfig
      STRATEGY_KEYS = %w[enabled weight].freeze
      PROFILE_KEYS = %w[strategies].freeze

      attr_reader :direct, :profiles

      def initialize(direct:, profiles:)
        @direct = normalized_weights(normalize_strategies(direct, enabled_by_default: false, context: "strategies"))
        @profiles = normalize_profiles(profiles)
      end

      private

      def normalize_strategies(raw, enabled_by_default:, context:)
        input!(raw.respond_to?(:to_h), "#{context} must be a mapping")
        stringify_keys(raw.to_h).to_h do |name, entry|
          validate_strategy_entry!(name, entry, context)
          normalized = normalize_strategy(entry.to_h, enabled_by_default, "#{context}.#{name}")
          [name, normalized]
        end
      end

      def validate_strategy_entry!(name, entry, context)
        input!(!name.empty?, "#{context} strategy name must not be empty")
        input!(registered_strategy?(name), "#{context}.#{name} is not a registered strategy")
        input!(entry.respond_to?(:to_h), "#{context}.#{name} must be a mapping")
      end

      def normalize_strategy(raw, enabled_by_default, context)
        entry = stringify_keys(raw)
        validate_strategy_keys!(entry, context)
        enabled = entry.fetch("enabled", enabled_by_default)
        validate_enabled!(enabled, context)
        weight = entry.fetch("weight", 0)
        validate_weight!(weight, enabled, context)
        entry.merge("enabled" => enabled, "weight" => enabled ? weight.to_f : 0.0)
      end

      def validate_strategy_keys!(entry, context)
        unknown = entry.keys - STRATEGY_KEYS
        input!(unknown.empty?, "#{context} has unknown keys: #{unknown.join(', ')}")
      end

      def validate_enabled!(enabled, context)
        input!([true, false].include?(enabled), "#{context}.enabled must be true or false")
      end

      def validate_weight!(weight, enabled, context)
        input!(weight.is_a?(Numeric), "#{context}.weight must be numeric")
        input!(!weight.negative?, "#{context}.weight must not be negative")
        input!(!enabled || weight.positive?, "#{context}.weight must be positive when enabled")
      end

      def normalize_profiles(raw)
        input!(raw.respond_to?(:to_h), "profiles must be a mapping")
        stringify_keys(raw.to_h).to_h { |name, profile| [name, normalize_profile(name, profile)] }
      end

      def normalize_profile(name, raw)
        input!(!name.empty?, "profile name must not be empty")
        input!(raw.respond_to?(:to_h), "profiles.#{name} must be a mapping")
        data = stringify_keys(raw.to_h)
        validate_profile_keys!(data, name)
        strategies = data["strategies"]
        input!(!strategies.nil?, "profiles.#{name}.strategies is required")
        normalized = normalize_strategies(strategies, enabled_by_default: true, context: "profiles.#{name}.strategies")
        input!(!normalized.empty?, "profiles.#{name}.strategies must not be empty")
        input!(normalized.any? { |_, entry| entry.fetch("enabled") },
               "profiles.#{name} must enable at least one strategy")
        normalized_weights(normalized)
      end

      def validate_profile_keys!(data, name)
        unknown = data.keys - PROFILE_KEYS
        input!(unknown.empty?, "profiles.#{name} has unknown keys: #{unknown.join(', ')}")
      end

      def normalized_weights(strategies)
        enabled = strategies.select { |_name, entry| entry.fetch("enabled") }
        return strategies.freeze if enabled.empty?

        total = enabled.values.sum { |entry| entry.fetch("weight") }
        input!(total.positive?, "enabled strategy weights must have a positive sum")
        strategies.to_h do |name, entry|
          weight = entry.fetch("enabled") ? entry.fetch("weight") / total : 0.0
          [name, entry.merge("weight" => weight).freeze]
        end.freeze
      end

      def registered_strategy?(name)
        SoftGoals::GOALS.any? { |goal| name == goal::KEY }
      end

      def stringify_keys(hash)
        hash.transform_keys(&:to_s)
      end

      def input!(condition, message)
        raise InvalidInputError, message unless condition
      end
    end
  end
end
