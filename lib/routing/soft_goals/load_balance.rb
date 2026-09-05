# frozen_string_literal: true

module Routing
  module SoftGoals
    class LoadBalance
      KEY = "load_balance"
      METRICS = %w[
        runtime.in_progress_count
        catalog.in_progress_count_limit
        runtime.in_progress_amount
        catalog.in_progress_amount_limit
        runtime.request_count
        catalog.requests_per_minute_limit
        runtime.daily_reserved_amount
        catalog.daily_amount_limit
        operation.amount
      ].freeze

      def self.call(provider, operation, _snapshot, _policy = nil)
        utilizations = [
          utilization(provider.in_progress_count + 1, provider.in_progress_count_limit),
          utilization(provider.in_progress_amount + operation.amount, provider.in_progress_amount_limit),
          rpm_utilization(provider, operation),
          utilization(provider.daily_approved_amount + operation.amount, provider.daily_amount_limit)
        ].compact
        return unlimited if utilizations.empty?

        load = utilizations.max.clamp(0.0, 1.0)
        score = 1.0 - load
        Contribution.new(
          name: KEY,
          score: score,
          reason: load >= 0.75 ? Reasons::HIGH_CURRENT_LOAD : Reasons::AVAILABLE_CAPACITY,
          details: "maximum load utilization #{(load * 100).round(2)}%"
        )
      end

      def self.rpm_utilization(provider, operation)
        limit = provider.requests_per_minute_limit
        return if limit.nil? || operation.created_at.nil?

        utilization(provider.request_count_at(operation.created_at) + 1, limit)
      end
      private_class_method :rpm_utilization

      def self.utilization(value, limit)
        return if limit.nil?
        return value.zero? ? 0.0 : 1.0 if limit.zero?

        value.to_f / limit
      end
      private_class_method :utilization

      def self.unlimited
        Contribution.new(name: KEY, score: 1.0, reason: Reasons::AVAILABLE_CAPACITY,
                         details: "no capacity limits configured")
      end
      private_class_method :unlimited
    end
  end
end
