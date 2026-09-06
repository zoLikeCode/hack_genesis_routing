# frozen_string_literal: true

module Routing
  class Engine
    module Setup
      private

      def validate_engine_inputs!(operations, providers, policy)
        Routing.assert(operations.respond_to?(:each), "operations must be enumerable")
        Routing.assert(providers.is_a?(ProviderPool), "providers must be a ProviderPool")
        Routing.assert(policy.is_a?(Policy), "policy must be Routing::Policy")
      end

      def initialize_runtime!(simulator, options)
        @simulator = simulator || Simulator.new(seed: @policy.simulation_seed)
        @state = options[:state] || RuntimeState.new(
          @providers, metrics_config: @policy.metrics, policy: @policy
        )
        @runtime_store = options[:runtime_store]
        Routing.assert(@runtime_store.nil? || @runtime_store.is_a?(RuntimeStore),
                       "runtime_store must be Routing::RuntimeStore")
        Routing.assert(@state.is_a?(RuntimeState), "state must be Routing::RuntimeState")
        Routing.assert(@state.providers.equal?(@providers), "runtime state must own the provider pool")
      end

      def initialize_status_checks!
        @circuit_breaker = CircuitBreaker.new(@policy.circuit_breaker)
        @status_checker = build_status_checker
        @status_check_runner = StatusCheckRunner.new(checker: @status_checker)
      end

      def initialize_tracking!
        @processed_ids = {}
        @operations_by_id = {}
        @decisions_by_id = {}
        @last_created_at = nil
      end
    end
  end
end
