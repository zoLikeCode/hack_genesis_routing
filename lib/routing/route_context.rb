# frozen_string_literal: true

module Routing
  class RouteContext
    attr_reader :attempts, :attempted, :temporarily_excluded, :total_latency

    def initialize(attempts: [], attempted: [], temporarily_excluded: [], total_latency: 0) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      Routing.assert(attempts.is_a?(Array) && attempts.all?(HardConstraints::Attempt),
                     "route context attempts must be Attempt objects")
      Routing.assert(attempted.is_a?(Array) && attempted.all? { |name| name.is_a?(String) && !name.empty? },
                     "route context attempted providers must be non-empty strings")
      Routing.assert(
        temporarily_excluded.is_a?(Array) &&
          temporarily_excluded.all? { |name| name.is_a?(String) && !name.empty? },
        "route context temporarily excluded providers must be non-empty strings"
      )
      Routing.assert(total_latency.is_a?(Numeric) && total_latency >= 0,
                     "route context latency must be non-negative")
      @attempts = attempts.dup
      @attempted = attempted.uniq
      @temporarily_excluded = temporarily_excluded.uniq
      @total_latency = total_latency
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

    def exclude_temporarily!(provider_name)
      Routing.assert(provider_name.is_a?(String) && !provider_name.empty?, "provider name required")
      @temporarily_excluded |= [provider_name]
    end

    def clear_temporarily_excluded!
      @temporarily_excluded = []
    end

    def add_latency!(latency)
      Routing.assert(latency.is_a?(Numeric) && latency >= 0, "latency must be non-negative")
      @total_latency += latency
    end
  end
end
