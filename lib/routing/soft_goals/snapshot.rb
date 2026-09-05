# frozen_string_literal: true

module Routing
  module SoftGoals
    class Snapshot
      attr_reader :version, :history, :metrics, :providers

      def self.from_providers(providers, **options)
        Routing.assert(providers.respond_to?(:each), "providers must be enumerable")
        providers = providers.to_a
        volumes, count_targets, volume_targets = provider_totals(providers)
        session_counts = options[:counts].nil? ? {} : options[:counts].to_h.dup
        providers.each { |provider| session_counts[provider.name] ||= 0 }
        snapshot = new(
          counts: session_counts, volumes: volumes, count_targets: count_targets,
          volume_targets: volume_targets, history: options[:history], metrics: options[:metrics],
          providers: providers, version: options.fetch(:version, 0)
        )
        snapshot.send(:make_readonly!) if options[:readonly]
        snapshot
      end

      def self.provider_totals(providers)
        volumes = {}
        count_targets = {}
        volume_targets = {}
        providers.each do |provider|
          Routing.assert(provider.is_a?(Provider), "snapshot requires Provider objects")
          name = provider.name
          volumes[name] = provider.daily_approved_amount
          count_targets[name] = provider.traffic_percentage
          volume_targets[name] = provider.volume_share_pct || 0
        end
        [volumes, count_targets, volume_targets]
      end
      private_class_method :provider_totals

      def initialize(counts: {}, volumes: {}, count_targets: {}, volume_targets: {}, **options)
        values = snapshot_values(options)
        validate_snapshot_values!(values)
        @counts = normalize_totals(counts, "counts")
        @volumes = normalize_totals(volumes, "volumes")
        @count_targets = normalize_totals(count_targets, "count_targets")
        @volume_targets = normalize_totals(volume_targets, "volume_targets")
        @history = values.fetch(:history)
        @metrics = values.fetch(:metrics)
        @providers = values.fetch(:providers).dup.freeze
        @version = values.fetch(:version)
        @readonly = false
      end

      def record_selection!(name)
        ensure_mutable!
        Routing.assert(name.is_a?(String) && !name.empty?, "provider name required")
        @counts[name] = count(name) + 1
        self
      end

      def record_approved_volume!(name, amount)
        ensure_mutable!
        Routing.assert(name.is_a?(String) && !name.empty?, "provider name required")
        Routing.assert(amount.is_a?(Numeric) && amount >= 0, "amount must be non-negative")
        @volumes[name] = volume(name) + amount
        self
      end

      def record!(name, amount)
        ensure_mutable!
        Routing.assert(name.is_a?(String) && !name.empty?, "provider name required")
        Routing.assert(amount.is_a?(Numeric) && amount >= 0, "amount must be non-negative")
        record_selection!(name)
        record_approved_volume!(name, amount)
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

      def count_totals
        @counts.dup.freeze
      end

      def volume_totals
        @volumes.dup.freeze
      end

      def count_targets
        @count_targets.dup.freeze
      end

      def volume_targets
        @volume_targets.dup.freeze
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

      def snapshot_values(options)
        {
          history: options.fetch(:history, nil), metrics: options.fetch(:metrics, nil),
          providers: options.fetch(:providers, []), version: options.fetch(:version, 0)
        }
      end

      def validate_snapshot_values!(values)
        Routing.assert(values.fetch(:version).is_a?(Integer) && values.fetch(:version) >= 0,
                       "snapshot version must be non-negative")
        Routing.assert(values.fetch(:history).nil? || values.fetch(:history).is_a?(History),
                       "snapshot history must be Routing::History")
        Routing.assert(values.fetch(:metrics).nil? || values.fetch(:metrics).is_a?(Metrics::Store),
                       "snapshot metrics must be Metrics::Store")
        providers = values.fetch(:providers)
        Routing.assert(providers.is_a?(Array) && providers.all?(Provider),
                       "snapshot providers must be Provider objects")
      end

      def ensure_mutable!
        Routing.assert(!@readonly, "cannot mutate a readonly snapshot")
      end

      def make_readonly!
        @readonly = true
        @counts.freeze
        @volumes.freeze
        @count_targets.freeze
        @volume_targets.freeze
      end

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
