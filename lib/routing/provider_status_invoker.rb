# frozen_string_literal: true

module Routing
  class ProviderStatusInvoker
    RESULTS = %w[approved rejected cancelled pending processing expired unknown].freeze

    def self.call(client:, provider:, task:)
      new(client, provider, task).call
    end

    def initialize(client, provider, task)
      @client = client
      @provider = provider
      @task = task
    end

    def call
      Routing.assert(@client.respond_to?(:status), "provider client must implement status")
      response = @client.status(
        @provider,
        operation_id: @task.reservation.operation_id,
        idempotency_key: @task.idempotency_key
      )
      validate!(response)
    end

    private

    def validate!(response)
      Routing.assert(response.respond_to?(:to_h), "provider status response must be a Hash")
      result = response.to_h[:result] || response.to_h["result"]
      Routing.assert(RESULTS.include?(result), "unknown provider status #{result}")
      result
    end
  end
end
