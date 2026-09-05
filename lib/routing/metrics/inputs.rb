# frozen_string_literal: true

module Routing
  module Metrics
    # Named observables a strategy may combine. Window quality (COMPONENTS) is
    # one family; session, catalog, runtime, and operation metrics are others.
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
        Entry.new("catalog.priority", "catalog"),
        Entry.new("operation.amount", "operation"),
        Entry.new("catalog.limit_amount_max", "catalog"),
        Entry.new("runtime.daily_approved_amount", "runtime"),
        Entry.new("catalog.daily_turnover_min", "catalog"),
        Entry.new("catalog.daily_turnover_max", "catalog"),
        Entry.new("runtime.in_progress_count", "runtime"),
        Entry.new("catalog.in_progress_count_limit", "catalog"),
        Entry.new("runtime.in_progress_amount", "runtime"),
        Entry.new("catalog.in_progress_amount_limit", "catalog"),
        Entry.new("runtime.request_count", "runtime"),
        Entry.new("catalog.requests_per_minute_limit", "catalog"),
        Entry.new("window.approval_rate", "window"),
        Entry.new("window.availability", "window"),
        Entry.new("window.acceptance", "window"),
        Entry.new("window.latency", "window"),
        Entry.new("window.health", "window")
      ].freeze

      HEALTH = %w[window.availability window.acceptance].freeze

      def self.keys
        ALL.map(&:key)
      end
    end
  end
end
