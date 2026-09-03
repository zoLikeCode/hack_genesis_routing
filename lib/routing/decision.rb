# frozen_string_literal: true

module Routing
  class Decision
    RESULTS = %w[approved rejected expired].freeze

    attr_reader :operation_id, :selected_provider, :attempts, :simulated_result, :latency_sec

    def initialize(operation_id:, selected_provider:, attempts:, simulated_result:, latency_sec:)
      Routing.assert(operation_id.is_a?(String) && !operation_id.empty?, "operation_id required")
      Routing.assert(selected_provider.is_a?(String) && !selected_provider.empty?, "selected_provider required")
      Routing.assert(attempts.is_a?(Array) && attempts.all?(HardConstraints::Attempt),
                     "attempts must be Attempt objects")
      Routing.assert(RESULTS.include?(simulated_result), "unknown simulated_result #{simulated_result}")
      Routing.assert(latency_sec.is_a?(Numeric), "latency_sec must be numeric")
      @operation_id = operation_id
      @selected_provider = selected_provider
      @attempts = attempts
      @simulated_result = simulated_result
      @latency_sec = latency_sec
    end

    def to_h
      {
        "operation_id" => operation_id,
        "selected_provider" => selected_provider,
        "attempts" => attempts.map(&:to_h),
        "simulated_result" => simulated_result,
        "latency_sec" => latency_sec
      }
    end
  end
end
