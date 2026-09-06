# frozen_string_literal: true

module Routing
  class Policy
    class ConcurrencyConfig
      def self.parse(raw)
        new(raw).to_h
      end

      def initialize(raw)
        Routing.input!(raw.respond_to?(:to_h), "concurrency must be a mapping")
        data = raw.to_h.transform_keys(&:to_s)
        @enabled = data.fetch("enabled", false)
        @executor = data.fetch("executor", "fiber_pool")
        @fallback_limit = data.fetch("fallback_worker_limit", 4)
        @max_per_provider = data.fetch("max_workers_per_provider", nil)
        @status_limit = data.fetch("status_worker_limit", 8)
        @debounce = data.fetch("persist_debounce_ms", 50)
        @event_log = data.fetch("event_log", false)
        validate!
      end

      def to_h
        {
          "enabled" => @enabled,
          "executor" => @executor,
          "fallback_worker_limit" => @fallback_limit,
          "max_workers_per_provider" => @max_per_provider,
          "status_worker_limit" => @status_limit,
          "persist_debounce_ms" => @debounce,
          "event_log" => @event_log
        }.freeze
      end

      private

      def validate!
        Routing.input!([true, false].include?(@enabled), "concurrency.enabled must be true or false")
        Routing.input!(%w[fiber_pool thread_pool].include?(@executor),
                       "concurrency.executor must be fiber_pool or thread_pool")
        Routing.input!(@fallback_limit.is_a?(Integer) && @fallback_limit.positive?,
                       "concurrency.fallback_worker_limit must be a positive integer")
        Routing.input!(@max_per_provider.nil? || (@max_per_provider.is_a?(Integer) && @max_per_provider.positive?),
                       "concurrency.max_workers_per_provider must be a positive integer")
        Routing.input!(@status_limit.is_a?(Integer) && @status_limit.positive?,
                       "concurrency.status_worker_limit must be a positive integer")
        Routing.input!(@debounce.is_a?(Integer) && @debounce >= 0,
                       "concurrency.persist_debounce_ms must be a non-negative integer")
        Routing.input!([true, false].include?(@event_log), "concurrency.event_log must be true or false")
      end
    end
  end
end
