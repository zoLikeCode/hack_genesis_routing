# frozen_string_literal: true

require "yaml"

module Routing
  class Policy
    DEFAULT_AMOUNT_BANDS = [
      { "max" => 50_000, "providers" => %w[payflow vipay quickpay] },
      { "max" => 100_000, "providers" => %w[vipay quickpay payflow] },
      { "max" => nil, "providers" => %w[quickpay vipay payflow] }
    ].freeze
    attr_reader :active_profile, :provider_profiles, :status_check, :circuit_breaker, :metrics, :amount_bands,
                :concurrency

    def self.load(path)
      new(parse(path))
    end

    def initialize(data)
      Routing.assert(data.respond_to?(:to_h), "policy must be a Hash")
      @data = stringify_keys(data.to_h)
      @metrics = Metrics::Config.parse(@data.fetch("metrics", {}))
      strategy_config = StrategyConfig.new(
        direct: @data.fetch("strategies", {}), profiles: @data.fetch("profiles", {})
      )
      @strategies = strategy_config.direct
      @profiles = strategy_config.profiles
      @amount_bands = AmountBands.new(@data.fetch("amount_bands", DEFAULT_AMOUNT_BANDS))
      @active_profile = normalize_active_profile(@data["active_profile"])
      @provider_profiles = normalize_provider_profiles(@data.fetch("provider_profiles", {}))
      configure_runtime_policy!
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

    def metrics_for(_provider = nil)
      metrics
    end

    def strategy_weights_for(provider = nil)
      strategies_for(provider).to_h { |name, entry| [name, entry.fetch("weight")] }
    end

    def amount_band_score(provider, amount)
      amount_bands.score(provider_name(provider), amount)
    end

    def validate_provider_targets!(providers)
      ProviderTargets.validate!(providers, self)
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

    def concurrency_enabled?
      concurrency.fetch("enabled")
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

    def configure_runtime_policy!
      @status_check = normalize_status_check(@data.fetch("status_check", {}))
      @circuit_breaker = normalize_circuit_breaker(@data.fetch("circuit_breaker", {}))
      @concurrency = ConcurrencyConfig.parse(@data.fetch("concurrency", {}))
    end

    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
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

    def normalize_status_check(raw)
      input_error!("status_check must be a mapping") unless raw.respond_to?(:to_h)
      data = stringify_keys(raw.to_h)
      enabled = data.fetch("enabled", true)
      initial_delay = data.fetch("initial_delay_sec", 5)
      retry_delays = data.fetch("retry_delays_sec", [5, 15, 30, 60])
      max_attempts = data.fetch("max_attempts", 5)
      validate_status_check!(enabled, initial_delay, retry_delays, max_attempts)

      {
        "enabled" => enabled,
        "initial_delay_sec" => initial_delay,
        "retry_delays_sec" => retry_delays.dup.freeze,
        "max_attempts" => max_attempts
      }.freeze
    end

    def validate_status_check!(enabled, initial_delay, retry_delays, max_attempts)
      input_error!("status_check.enabled must be true or false") unless [true, false].include?(enabled)
      input_error!("status_check.initial_delay_sec must be non-negative") unless non_negative_number?(initial_delay)
      unless valid_retry_delays?(retry_delays)
        input_error!("status_check.retry_delays_sec must be a non-empty list of non-negative numbers")
      end
      return if max_attempts.is_a?(Integer) && max_attempts.positive?

      input_error!("status_check.max_attempts must be a positive integer")
    end

    def valid_retry_delays?(retry_delays)
      retry_delays.is_a?(Array) && !retry_delays.empty? && retry_delays.all? do |delay|
        non_negative_number?(delay)
      end
    end

    def non_negative_number?(value)
      value.is_a?(Numeric) && value >= 0
    end

    def validate_strategy_source!
      validate_active_profile!
      validate_provider_profiles!
      if !profiles_selected? && !direct_strategy_enabled?
        input_error!("individual strategy mode must enable at least one strategy")
      end
      return unless profiles_selected? && direct_strategy_enabled?

      source = active_profile.nil? ? "provider_profiles" : "active_profile"
      input_error!("#{source} cannot be used while an individual strategy is enabled")
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

    def normalize_circuit_breaker(raw)
      input_error!("circuit_breaker must be a mapping") unless raw.respond_to?(:to_h)
      data = stringify_keys(raw.to_h)
      enabled = data.fetch("enabled", true)
      count_limit = data.fetch("unresolved_count_limit", 5)
      amount_limit = data.fetch("unresolved_amount_limit", 500_000)
      input_error!("circuit_breaker.enabled must be true or false") unless [true, false].include?(enabled)
      unless count_limit.is_a?(Integer) && count_limit.positive?
        input_error!("circuit_breaker.unresolved_count_limit must be a positive integer")
      end
      unless amount_limit.is_a?(Numeric) && amount_limit.positive?
        input_error!("circuit_breaker.unresolved_amount_limit must be positive")
      end
      {
        "enabled" => enabled,
        "unresolved_count_limit" => count_limit,
        "unresolved_amount_limit" => amount_limit
      }.freeze
    end

    def direct_strategy_enabled?
      @strategies.any? { |_name, entry| entry.fetch("enabled") }
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
