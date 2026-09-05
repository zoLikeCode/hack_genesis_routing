# frozen_string_literal: true

module Routing
  class Policy
    class ProviderTargets
      STRATEGIES = {
        "count_share" => :traffic_percentage,
        "volume_share" => :volume_share_pct
      }.freeze

      def self.validate!(providers, policy)
        list = providers.to_a
        STRATEGIES.each do |strategy, attribute|
          next unless enabled_for_primary?(strategy, list, policy)

          validate_values!(strategy, list.map { |provider| provider.public_send(attribute) || 0 })
        end
      end

      def self.enabled_for_primary?(strategy, providers, policy)
        providers.any? do |provider|
          provider.primary?(fallback: policy.fallback_provider) && policy.enabled?(strategy, provider: provider.name)
        end
      end
      private_class_method :enabled_for_primary?

      def self.validate_values!(strategy, values)
        valid = values.all? { |value| value.is_a?(Numeric) && value.between?(0, 100) }
        Routing.input!(valid, "#{strategy} targets must be numeric percentages in [0, 100]")
        total = values.sum(&:to_f)
        Routing.input!((total - 100.0).abs <= 1e-6, "#{strategy} targets must sum to 100 (got #{total})")
      end
      private_class_method :validate_values!
    end
  end
end
