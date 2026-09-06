# frozen_string_literal: true

module Routing
  class ReplaySimulator
    def initialize(client:, clock:)
      @client = client
      @clock = clock
    end

    def call(...)
      outcome = @client.call(...)
      Async::Task.current.sleep(@clock.real_delay(outcome.fetch(:latency_sec)))
      outcome
    end

    def status(...)
      @client.status(...)
    end
  end
end
