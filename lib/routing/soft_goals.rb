# frozen_string_literal: true

module Routing
  module SoftGoals
    # A strategy combines metrics into one score in [0, 1]. A profile combines
    # strategies using normalized positive weights. There are no extra score
    # multipliers after the profile mix.
    #
    # To add a metric that should affect selection:
    #   1. Register it in Metrics::Inputs
    #   2. Produce the value (catalog, session, window, runtime, or operation)
    #   3. List it on an existing SoftGoals::*::METRICS, or add a class to GOALS
    GOALS = [
      CountShare,
      VolumeShare,
      Conversion,
      CascadePriority,
      AmountBand,
      FinancialObligation,
      LoadBalance
    ].freeze

    METRIC_STRATEGY_KEY = Conversion::KEY

    def self.metrics_for(goal)
      Array(goal::METRICS)
    end

    def self.metric_map
      GOALS.to_h { |goal| [goal::KEY, metrics_for(goal)] }
    end
  end
end
