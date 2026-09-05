# frozen_string_literal: true

module Routing
  module Metrics
    class Store
      attr_reader :config

      def self.seed(history:, providers:, config:, config_for: nil)
        Routing.assert(providers.respond_to?(:each), "metrics store requires providers")
        Routing.assert(config_for.nil? || config_for.respond_to?(:call), "config_for must be callable")
        resolved = resolve_config(config)
        windows = {}
        providers.each do |provider|
          Routing.assert(provider.is_a?(Provider), "metrics store requires Provider objects")
          cfg = provider_config(resolved, config_for, provider)
          windows[provider.name] = Window.new(
            max_observations: cfg.max_observations,
            observations: seeded_observations(history, provider, cfg.max_observations)
          )
        end
        new(windows, resolved)
      end

      def initialize(windows, config, readonly: false)
        Routing.assert(windows.is_a?(Hash), "metrics windows must be a Hash")
        Routing.assert(windows.values.all?(Window), "metrics windows must be Window objects")
        @config = self.class.resolve_config(config)
        @windows = windows
        @readonly = readonly
      end

      def record(observation)
        ensure_mutable!
        Routing.assert(observation.is_a?(History::Observation), "metrics record requires Observation")
        window_for(observation.provider_name).record(observation)
        self
      end

      def update_status(operation_id:, provider_name:, status:, observation: nil, latency_sec: :clear)
        ensure_mutable!
        Routing.assert(provider_name.is_a?(String) && !provider_name.empty?, "provider name required")
        mapped = status == "cancelled" ? "rejected" : status
        window = window_for(provider_name)
        return self if window.rewrite_status(operation_id: operation_id, status: mapped, latency_sec: latency_sec)
        return self if observation.nil?

        Routing.assert(observation.is_a?(History::Observation), "metrics restore requires Observation")
        window.record(observation.with(status: mapped, latency_sec: restored_latency(observation, latency_sec)))
        self
      end

      def window(name)
        @windows[name] || Window.new(max_observations: @config.max_observations)
      end

      def observations_for(name)
        stored = @windows[name]
        stored.nil? ? [].freeze : stored.observations
      end

      def snapshot
        frozen = @windows.transform_values(&:freeze_copy)
        self.class.new(frozen, @config, readonly: true)
      end

      def names
        @windows.keys
      end

      def self.resolve_config(config)
        return config if config.is_a?(Config)
        return Config.default if config.nil?

        Config.parse(config)
      end

      def self.provider_config(resolved, config_for, provider)
        return resolved if config_for.nil?

        extra = config_for.call(provider)
        extra.is_a?(Config) ? extra : resolve_config(extra)
      end
      private_class_method :provider_config

      def self.seeded_observations(history, provider, max_observations)
        return [] if history.nil?

        Routing.assert(history.is_a?(History), "metrics seed history must be Routing::History")
        rows = history.observations_for(provider.name).select { |row| Metrics.compatible?(provider, row) }
        rows.each_with_index.sort_by { |row, index| [row.created_at, index] }.map(&:first).last(max_observations)
      end
      private_class_method :seeded_observations

      private

      def restored_latency(_observation, latency_sec)
        latency_sec == :clear ? nil : latency_sec
      end

      def window_for(name)
        @windows[name] ||= Window.new(max_observations: @config.max_observations)
      end

      def ensure_mutable!
        Routing.assert(!@readonly, "cannot mutate a frozen metrics store")
      end
    end
  end
end
