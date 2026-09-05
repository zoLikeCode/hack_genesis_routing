# frozen_string_literal: true

module Routing
  module Metrics
    module ConfigDefaults
      HASH = {
        "window" => { "max_observations" => 50, "lookback_hours" => 24.0 },
        "smoothing" => {
          "prior_strength" => 10.0,
          "default_conversion_prior" => 0.5,
          "segment_min_size" => 10,
          "segment_prior_strength" => 10.0
        }
      }.freeze
    end
  end
end
