# frozen_string_literal: true

module Routing
  class RouteContext
    attr_reader :attempts, :attempted, :total_latency

    def initialize
      @attempts = []
      @attempted = []
      @total_latency = 0
    end

    def merge_skips!(skipped)
      Routing.assert(skipped.respond_to?(:each), "skipped attempts must be enumerable")
      seen = attempts.map { |attempt| [attempt.provider, attempt.reason] }
      skipped.each do |attempt|
        Routing.assert(attempt.is_a?(HardConstraints::Attempt), "skip must be a routing attempt")
        attempts << attempt unless seen.include?([attempt.provider, attempt.reason])
      end
    end

    def add_attempt!(attempt)
      Routing.assert(attempt.is_a?(HardConstraints::Attempt), "attempt must be a routing attempt")
      attempts << attempt
    end

    def mark_attempted!(provider_name)
      Routing.assert(provider_name.is_a?(String) && !provider_name.empty?, "provider name required")
      @attempted |= [provider_name]
    end

    def add_latency!(latency)
      Routing.assert(latency.is_a?(Numeric) && latency >= 0, "latency must be non-negative")
      @total_latency += latency
    end
  end
end
