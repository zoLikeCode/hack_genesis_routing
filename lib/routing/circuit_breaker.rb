# frozen_string_literal: true

module Routing
  class CircuitBreaker
    def self.disabled
      new(
        "enabled" => false,
        "unresolved_count_limit" => 1,
        "unresolved_amount_limit" => 1
      )
    end

    def initialize(config)
      Routing.assert(config.respond_to?(:to_h), "circuit breaker config must be a Hash")
      @config = config.to_h
      @unresolved = Hash.new { |hash, name| hash[name] = {} }
      @mutex = Mutex.new
    end

    def record_unresolved!(reservation)
      Routing.assert(reservation.is_a?(Reservation), "circuit breaker requires a Reservation")
      @mutex.synchronize do
        @unresolved[reservation.provider_name][reservation.idempotency_key] = reservation.amount
      end
      self
    end

    def open?(provider_name)
      return false unless @config.fetch("enabled")

      @mutex.synchronize { threshold_reached?(@unresolved[provider_name]) }
    end

    def open_provider_names
      @mutex.synchronize do
        next [].freeze unless @config.fetch("enabled")

        @unresolved.filter_map { |name, entries| name if threshold_reached?(entries) }.freeze
      end
    end

    def summary
      @mutex.synchronize do
        @unresolved.to_h do |name, entries|
          [
            name,
            {
              "status" => threshold_reached?(entries) ? "open" : "closed",
              "unresolved_count" => entries.size,
              "unresolved_amount" => entries.values.sum
            }
          ]
        end
      end
    end

    private

    def threshold_reached?(entries)
      entries.size >= @config.fetch("unresolved_count_limit") ||
        entries.values.sum >= @config.fetch("unresolved_amount_limit")
    end
  end
end
