# frozen_string_literal: true

require "yaml"

module Routing
  class Policy
    attr_reader :active_profile, :provider_profiles

    def self.load(path)
      new(parse(path))
    end

    def initialize(data)
      Routing.assert(data.respond_to?(:to_h), "policy must be a Hash")
      @data = stringify_keys(data.to_h)
      @strategies = normalize_strategies(
        @data.fetch("strategies", {}),
        enabled_by_default: false,
        context: "strategies"
      )
      @profiles = normalize_profiles(@data.fetch("profiles", {}))
      @active_profile = normalize_active_profile(@data["active_profile"])
      @provider_profiles = normalize_provider_profiles(@data.fetch("provider_profiles", {}))
      validate_strategy_source!
      @active_strategies = resolve_active_strategies
    end

    def weight_for(key, provider: nil)
      entry = strategies_for(provider)[key.to_s]
      return 0 if entry.nil?

      entry.fetch("weight")
    end

    def enabled?(key, provider: nil)
      !weight_for(key, provider: provider).zero?
    end

    def profile_for(provider)
      @provider_profiles[provider_name(provider)] || active_profile
    end

    def fallback_provider
      name = @data.fetch("fallback_provider", "spacepayments")
      Routing.assert(name.is_a?(String) && !name.empty?, "fallback_provider required")
      name
    end

    def simulation_seed
      seed = @data.fetch("simulation_seed", 42)
      Routing.assert(seed.is_a?(Integer), "simulation_seed must be an Integer")
      seed
    end

    def default_requests_per_minute_limit
      raw = @data["hard_constraints"]
      return if raw.nil?

      Routing.assert(raw.respond_to?(:to_h), "hard_constraints must be a mapping")
      limit = stringify_keys(raw.to_h)["default_requests_per_minute_limit"]
      return if limit.nil?

      Routing.assert(limit.is_a?(Integer) && limit >= 0,
                     "default_requests_per_minute_limit must be a non-negative integer")
      limit
    end

    def self.parse(path)
      data = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
      raise InvalidInputError, "#{path}: policy must be a mapping" unless data.is_a?(Hash)

      data
    rescue Psych::SyntaxError, Errno::ENOENT => e
      raise InvalidInputError, "#{path}: #{e.message}"
    end
    private_class_method :parse

    private

    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end

    def normalize_strategies(raw, enabled_by_default:, context:)
      input_error!("#{context} must be a mapping") unless raw.respond_to?(:to_h)

      stringify_keys(raw.to_h).to_h do |name, entry|
        input_error!("#{context} strategy name must not be empty") if name.empty?
        input_error!("#{context}.#{name} is not a registered strategy") unless registered_strategy?(name)
        input_error!("#{context}.#{name} must be a mapping") unless entry.respond_to?(:to_h)

        [name, normalize_strategy(entry.to_h, enabled_by_default: enabled_by_default, context: "#{context}.#{name}")]
      end
    end

    def normalize_strategy(raw, enabled_by_default:, context:)
      entry = stringify_keys(raw)
      enabled = entry.fetch("enabled", enabled_by_default)
      input_error!("#{context}.enabled must be true or false") unless [true, false].include?(enabled)

      weight = entry.fetch("weight", 0)
      input_error!("#{context}.weight must be numeric") unless weight.is_a?(Numeric)
      input_error!("#{context}.weight must not be negative") if weight.negative?
      input_error!("#{context}.weight must be positive when enabled") if enabled && !weight.positive?

      entry.merge("enabled" => enabled, "weight" => weight)
    end

    def registered_strategy?(name)
      SoftGoals::GOALS.any? { |goal| name == goal::KEY }
    end

    def normalize_profiles(raw)
      input_error!("profiles must be a mapping") unless raw.respond_to?(:to_h)

      stringify_keys(raw.to_h).to_h do |name, profile|
        [name, normalize_profile(name, profile)]
      end
    end

    def normalize_profile(name, raw)
      input_error!("profile name must not be empty") if name.empty?
      input_error!("profiles.#{name} must be a mapping") unless raw.respond_to?(:to_h)

      strategies = stringify_keys(raw.to_h)["strategies"]
      input_error!("profiles.#{name}.strategies is required") if strategies.nil?
      normalized = normalize_strategies(
        strategies,
        enabled_by_default: true,
        context: "profiles.#{name}.strategies"
      )
      input_error!("profiles.#{name}.strategies must not be empty") if normalized.empty?
      enabled = normalized.any? { |_, entry| entry.fetch("enabled") }
      input_error!("profiles.#{name} must enable at least one strategy") unless enabled
      normalized
    end

    def normalize_active_profile(value)
      return if value.nil?

      input_error!("active_profile must be a non-empty string") unless value.is_a?(String) && !value.empty?
      value
    end

    def normalize_provider_profiles(raw)
      input_error!("provider_profiles must be a mapping") unless raw.respond_to?(:to_h)

      stringify_keys(raw.to_h).to_h do |provider, profile|
        input_error!("provider_profiles provider name must not be empty") if provider.empty?
        unless profile.is_a?(String) && !profile.empty?
          input_error!("provider_profiles.#{provider} must be a non-empty string")
        end
        [provider, profile]
      end.freeze
    end

    def validate_strategy_source!
      validate_active_profile!
      validate_provider_profiles!
      return unless profiles_selected?
      return unless @strategies.any? { |_, entry| entry.fetch("enabled") }

      input_error!("provider_profiles cannot be used while an individual strategy is enabled") if active_profile.nil?
      input_error!("active_profile cannot be used while an individual strategy is enabled")
    end

    def validate_active_profile!
      return if active_profile.nil? || @profiles.key?(active_profile)

      input_error!("unknown active_profile #{active_profile}")
    end

    def validate_provider_profiles!
      @provider_profiles.each do |provider, profile|
        next if @profiles.key?(profile)

        input_error!("unknown profile #{profile} for provider #{provider}")
      end
    end

    def profiles_selected?
      !active_profile.nil? || !@provider_profiles.empty?
    end

    def resolve_active_strategies
      source = active_profile.nil? ? @strategies : @profiles.fetch(active_profile)
      source.select { |_, entry| entry.fetch("enabled") }.freeze
    end

    def strategies_for(provider)
      profile = provider.nil? ? active_profile : profile_for(provider)
      return @profiles.fetch(profile) unless profile.nil?

      @active_strategies
    end

    def provider_name(provider)
      return provider.name if provider.respond_to?(:name)

      provider.to_s
    end

    def input_error!(message)
      raise InvalidInputError, message
    end
  end
end
