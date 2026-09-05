# frozen_string_literal: true

module Routing
  module Metrics
    # Named observables a strategy may combine. Conversion deliberately uses
    # one quality signal: the probability of an initial approved response.
    #
    # A new metric becomes a routing decision when a SoftGoals::* strategy
    # lists it in METRICS (existing class or a new one on SoftGoals::GOALS).
    module Inputs
      SOURCES = %w[session catalog window runtime operation].freeze
      Entry = Data.define(:key, :source)

      ALL = [
        Entry.new("session.count_share_pct", "session"),
        Entry.new("catalog.traffic_percentage", "catalog"),
        Entry.new("session.volume_share_pct", "session"),
        Entry.new("catalog.volume_share_pct", "catalog"),
        Entry.new("catalog.conversion_24h", "catalog"),
        Entry.new("window.initial_conversion", "window"),
        Entry.new("catalog.priority", "catalog"),
        Entry.new("operation.amount", "operation"),
        Entry.new("catalog.amount_band_preferences", "catalog"),
        Entry.new("runtime.daily_approved_amount", "runtime"),
        Entry.new("catalog.daily_turnover_min", "catalog"),
        Entry.new("catalog.daily_turnover_max", "catalog"),
        Entry.new("runtime.in_progress_count", "runtime"),
        Entry.new("catalog.in_progress_count_limit", "catalog"),
        Entry.new("runtime.in_progress_amount", "runtime"),
        Entry.new("catalog.in_progress_amount_limit", "catalog"),
        Entry.new("runtime.request_count", "runtime"),
        Entry.new("catalog.requests_per_minute_limit", "catalog"),
        Entry.new("runtime.daily_reserved_amount", "runtime"),
        Entry.new("catalog.daily_amount_limit", "catalog")
      ].freeze

      def self.keys
        ALL.map(&:key)
      end
    end
  end
end
