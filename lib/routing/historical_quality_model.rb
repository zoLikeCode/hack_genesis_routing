# frozen_string_literal: true

module Routing
  class HistoricalQualityModel
    def self.call(observations:, provider:, operation:, config: nil)
      Metrics::Catalog.call(
        observations: observations,
        provider: provider,
        operation: operation,
        config: config
      )
    end
  end
end
