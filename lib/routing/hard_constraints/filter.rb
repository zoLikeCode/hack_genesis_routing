# frozen_string_literal: true

module Routing
  module HardConstraints
    class Filter
      def self.call(operation:, providers:, fallback: "spacepayments", at: nil)
        new(operation, providers, fallback, at).call
      end

      def initialize(operation, providers, fallback, at)
        Routing.assert(operation.is_a?(Operation), "operation must be Routing::Operation")
        Routing.assert(fallback.is_a?(String) && !fallback.empty?, "fallback name required")
        @operation = operation
        @providers = providers
        @fallback = fallback
        @at = at
      end

      def call
        eligible = []
        skipped = []
        fallback_provider = nil

        @providers.each do |provider|
          classify(provider, eligible, skipped) { fallback_provider = provider }
        end

        Evaluation.new(eligible: eligible, skipped: skipped, fallback: fallback_provider)
      end

      private

      def classify(provider, eligible, skipped)
        primary = provider.primary?(fallback: @fallback)
        return unless primary || provider.name == @fallback

        result = evaluate(provider)
        if result.ok?
          primary ? eligible << provider : yield
        elsif primary
          skipped << skip_attempt(provider, result)
        end
      end

      def evaluate(provider)
        HardConstraints.evaluate(provider, @operation, at: @at)
      end

      def skip_attempt(provider, result)
        Attempt.new(
          provider: provider.name,
          decision: "skipped",
          reason: result.reason,
          details: result.details
        )
      end
    end
  end
end
