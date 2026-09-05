# frozen_string_literal: true

module Routing
  module SoftGoals
    module ShareFit
      Result = Data.define(:score, :before_error, :after_error, :before_share, :after_share, :target_share)

      def self.call(candidates:, totals:, targets:, increment:)
        validate_targets!(targets)
        before_error = distribution_error(totals, targets)
        candidates.to_h do |provider|
          projected = totals.merge(provider.name => totals.fetch(provider.name, 0) + increment.call(provider))
          after_error = distribution_error(projected, targets)
          [provider.name, Result.new(
            score: (1.0 - after_error).clamp(0.0, 1.0),
            before_error: before_error, after_error: after_error,
            before_share: share(totals, provider.name), after_share: share(projected, provider.name),
            target_share: targets.fetch(provider.name, 0).to_f / 100.0
          )]
        end
      end

      def self.validate_targets!(targets)
        valid = targets.values.all? { |value| value.is_a?(Numeric) && value.between?(0, 100) }
        Routing.input!(valid, "enabled share targets must be numeric percentages in [0, 100]")
        total = targets.values.sum(&:to_f)
        Routing.input!((total - 100.0).abs <= 1e-6, "enabled share targets must sum to 100 (got #{total})")
      end
      private_class_method :validate_targets!

      def self.distribution_error(totals, targets)
        names = totals.keys | targets.keys
        0.5 * names.sum do |name|
          delta = share(totals, name) - (targets.fetch(name, 0).to_f / 100.0)
          delta * delta
        end
      end
      private_class_method :distribution_error

      def self.share(totals, name)
        total = totals.values.sum.to_f
        return 0.0 if total.zero?

        totals.fetch(name, 0).to_f / total
      end
      private_class_method :share
    end
  end
end
