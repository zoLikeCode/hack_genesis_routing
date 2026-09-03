# frozen_string_literal: true

module Routing
  module HardConstraints
    class Attempt
      attr_reader :provider, :decision, :reason, :details

      DECISIONS = %w[selected skipped].freeze

      def initialize(provider:, decision:, reason:, details: nil)
        Routing.assert(provider.is_a?(String) && !provider.empty?, "attempt provider required")
        Routing.assert(DECISIONS.include?(decision), "unknown decision #{decision}")
        Routing.assert(reason.is_a?(String) && !reason.empty?, "attempt reason required")
        @provider = provider
        @decision = decision
        @reason = reason
        @details = details
      end

      def to_h
        hash = { "provider" => provider, "decision" => decision, "reason" => reason }
        hash["details"] = details unless details.nil?
        hash
      end
    end
  end
end
