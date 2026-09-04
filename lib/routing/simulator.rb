# frozen_string_literal: true

module Routing
  class Simulator
    REJECTED = "simulated_rejected"
    EXPIRED = "simulated_expired"

    def initialize(seed:)
      Routing.assert(seed.is_a?(Integer), "simulation seed must be an Integer")
      @rng = Random.new(seed)
      @status_rng = Random.new(seed ^ 0x5A17)
      @status_results = {}
    end

    def call(provider, operation: nil, idempotency_key: nil)
      Routing.assert(provider.is_a?(Provider), "provider must be Routing::Provider")
      Routing.assert(operation.nil? || operation.is_a?(Operation), "operation must be Routing::Operation")
      Routing.assert(idempotency_key.nil? || !idempotency_key.empty?, "idempotency key must not be empty")
      conversion = conversion_for(provider)
      result = roll_result(conversion)
      remember_timeout(idempotency_key, conversion) if result == "expired" && !idempotency_key.nil?
      { result: result, latency_sec: latency_for(provider) }
    end

    def status(provider, operation_id:, idempotency_key:)
      Routing.assert(provider.is_a?(Provider), "provider must be Routing::Provider")
      Routing.assert(operation_id.is_a?(String) && !operation_id.empty?, "operation id required")
      Routing.assert(idempotency_key.is_a?(String) && !idempotency_key.empty?, "idempotency key required")
      result = @status_results[idempotency_key]
      Routing.assert(!result.nil?, "unknown simulated payout #{idempotency_key}")
      { result: result }
    end

    private

    def conversion_for(provider)
      value = provider.conversion_24h
      return 1.0 if value.nil?

      Routing.assert(value.between?(0, 1), "conversion_24h must be in [0, 1]")
      value.to_f
    end

    def roll_result(conversion)
      roll = @rng.rand
      return "approved" if roll < conversion

      midpoint = conversion + ((1.0 - conversion) / 2.0)
      roll < midpoint ? "rejected" : "expired"
    end

    def latency_for(provider)
      value = provider.avg_latency_sec
      return 0 if value.nil?

      value.round
    end

    def remember_timeout(idempotency_key, conversion)
      @status_results[idempotency_key] ||= @status_rng.rand < conversion ? "approved" : "rejected"
    end
  end
end
