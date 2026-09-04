# frozen_string_literal: true

module Routing
  module SoftGoals
    module Reasons
      COUNT_SHARE_DEFICIT = "count_share_deficit"
      COUNT_SHARE_OVER_TARGET = "count_share_over_target"
      VOLUME_SHARE_DEFICIT = "volume_share_deficit"
      VOLUME_SHARE_OVER_TARGET = "volume_share_over_target"
      HIGHER_CONVERSION = "higher_conversion"
      HISTORICAL_QUALITY = "historical_quality"
      CASCADE_PRIORITY = "cascade_priority"
      AMOUNT_BAND_FIT = "amount_band_fit"
      AVAILABLE_CAPACITY = "available_capacity"
      HIGH_CURRENT_LOAD = "high_current_load"
      TURNOVER_BELOW_MINIMUM = "turnover_below_minimum"
      TURNOVER_ABOVE_SOFT_MAX = "turnover_above_soft_max"
      ONLY_ELIGIBLE_PROVIDER = "only_eligible_provider"
      HIGHEST_SOFT_SCORE = "highest_soft_score"
      LOWER_SOFT_SCORE = "lower_soft_score"
      NEUTRAL = "soft_goal_neutral"
      UNMET_COUNT_SHARE = "unmet_count_share"
      UNMET_VOLUME_SHARE = "unmet_volume_share"
      GOAL_DISAGREEMENT = "goal_disagreement"
      METRIC_DISAGREEMENT = "metric_disagreement"
    end
  end
end
