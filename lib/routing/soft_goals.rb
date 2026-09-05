# frozen_string_literal: true

module Routing
  module SoftGoals
    # A strategy combines metrics into one score in [-1, 1]. A profile combines
    # strategies. Health is also a metric combination, applied after the mix.
    #
    # To add a metric that should affect selection:
    #   1. Register it in Metrics::Inputs
    #   2. Produce the value (catalog, session, window, runtime, or operation)
    #   3. List it on an existing SoftGoals::*::METRICS, or add a class to GOALS
    GOALS = [
      CountShare,
      VolumeShare,
      Conversion,
      HistoricalQuality,
      CascadePriority,
      AmountBand,
      FinancialObligation,
      LoadBalance
    ].freeze

    METRIC_STRATEGY_KEY = HistoricalQuality::KEY

    def self.metrics_for(goal)
      Array(goal::METRICS)
    end

    def self.metric_map
      GOALS.to_h { |goal| [goal::KEY, metrics_for(goal)] }
    end

    def self.deficit_score(target, actual)
      return 0.0 if target.nil?

      ((target.to_f - actual.to_f) / 100.0).clamp(-1.0, 1.0)
    end
  end
end
