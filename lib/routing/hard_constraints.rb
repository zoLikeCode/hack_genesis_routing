# frozen_string_literal: true

module Routing
  module HardConstraints
    CHECKS = [
      Status,
      AmountRange,
      DailyLimit,
      InProgress,
      BankFilter,
      Margin,
      Requisites,
      Intensity
    ].freeze

    def self.evaluate(provider, operation)
      Routing.assert(provider.is_a?(Provider), "provider must be Routing::Provider")
      Routing.assert(operation.is_a?(Operation), "operation must be Routing::Operation")
      CHECKS.each do |check|
        result = check.call(provider, operation)
        return result if result.skipped?
      end
      Result.ok
    end
  end
end
