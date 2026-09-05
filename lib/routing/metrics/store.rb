# frozen_string_literal: true

module Routing
  module Metrics
    class Store
      attr_reader :config

      def self.seed(history:, providers:, config:)
        Routing.assert(providers.respond_to?(:each), "metrics store requires providers")
        resolved = resolve_config(config)
        windows = {}
        providers.each do |provider|
          Routing.assert(provider.is_a?(Provider), "metrics store requires Provider objects")
          windows[provider.name] = Window.new(
            observations: seeded_observations(history, provider)
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

      def update_status(operation_id:, provider_name:, status:)
        ensure_mutable!
        Routing.assert(provider_name.is_a?(String) && !provider_name.empty?, "provider name required")
        mapped = status == "cancelled" ? "rejected" : status
        window_for(provider_name).rewrite_status(operation_id: operation_id, status: mapped)
        self
      end

      def window(name)
        @windows[name] || Window.new
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

      def self.seeded_observations(history, provider)
        return [] if history.nil?

        Routing.assert(history.is_a?(History), "metrics seed history must be Routing::History")
        history.observations_for(provider.name)
      end
      private_class_method :seeded_observations

      private

      def window_for(name)
        @windows[name] ||= Window.new
      end

      def ensure_mutable!
        Routing.assert(!@readonly, "cannot mutate a frozen metrics store")
      end
    end
  end
end
