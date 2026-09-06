# frozen_string_literal: true

module Routing
  class ProviderInvoker
    def self.call(client:, provider:, operation:, reservation:)
      new(client, provider, operation, reservation).call
    end

    def initialize(client, provider, operation, reservation)
      @client = client
      @provider = provider
      @operation = operation
      @reservation = reservation
    end

    def call
      outcome = accepts_keywords? ? call_with_context : @client.call(@provider)
      validate!(outcome)
    end

    private

    def accepts_keywords?
      @client.method(:call).parameters.any? { |kind, _| %i[key keyreq keyrest].include?(kind) }
    end

    def call_with_context
      @client.call(
        @provider,
        operation: @operation,
        idempotency_key: @reservation.idempotency_key
      )
    end

    def validate!(outcome)
      raise IOError, "provider outcome must be a Hash" unless outcome.respond_to?(:to_h)

      result = outcome.to_h
      raise IOError, "unknown simulated result #{result[:result]}" unless Decision::RESULTS.include?(result[:result])
      unless result[:latency_sec].is_a?(Numeric) && result[:latency_sec] >= 0
        raise IOError, "latency_sec must be non-negative"
      end

      result
    end
  end
end
