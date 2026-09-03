# frozen_string_literal: true

module Routing
  module SoftGoals
    class Snapshot
      def self.from_providers(providers)
        Routing.assert(providers.respond_to?(:each), "providers must be enumerable")
        counts = {}
        volumes = {}
        count_targets = {}
        volume_targets = {}
        providers.each do |provider|
          Routing.assert(provider.is_a?(Provider), "snapshot requires Provider objects")
          name = provider.name
          counts[name] = 0
          volumes[name] = provider.daily_approved_amount
          count_targets[name] = provider.traffic_percentage
          volume_targets[name] = provider.volume_share_pct || 0
        end
        new(counts: counts, volumes: volumes, count_targets: count_targets, volume_targets: volume_targets)
      end

      def initialize(counts: {}, volumes: {}, count_targets: {}, volume_targets: {})
        @counts = normalize_totals(counts, "counts")
        @volumes = normalize_totals(volumes, "volumes")
        @count_targets = normalize_totals(count_targets, "count_targets")
        @volume_targets = normalize_totals(volume_targets, "volume_targets")
      end

      def record!(name, amount)
        Routing.assert(name.is_a?(String) && !name.empty?, "provider name required")
        Routing.assert(amount.is_a?(Numeric) && amount >= 0, "amount must be non-negative")
        @counts[name] = count(name) + 1
        @volumes[name] = volume(name) + amount
        self
      end

      def count(name)
        @counts.fetch(name, 0)
      end

      def volume(name)
        @volumes.fetch(name, 0)
      end

      def total_count
        @counts.values.sum
      end

      def total_volume
        @volumes.values.sum
      end

      def count_share_pct(name)
        share_pct(count(name), total_count)
      end

      def volume_share_pct(name)
        share_pct(volume(name), total_volume)
      end

      def unmet_count_targets(eligible_names)
        unmet(@count_targets, eligible_names)
      end

      def unmet_volume_targets(eligible_names)
        unmet(@volume_targets, eligible_names)
      end

      private

      def share_pct(part, total)
        return 0.0 if total.zero?

        100.0 * part / total
      end

      def unmet(targets, eligible_names)
        names = eligible_names.to_a
        targets.select { |name, pct| pct.positive? && !names.include?(name) }.keys
      end

      def normalize_totals(hash, field)
        Routing.assert(hash.respond_to?(:to_h), "#{field} must be a Hash")
        hash.to_h { |key, value| [key.to_s, non_negative(value, field)] }
      end

      def non_negative(value, field)
        Routing.assert(value.is_a?(Numeric) && value >= 0, "#{field} values must be non-negative")
        value
      end
    end
  end
end
