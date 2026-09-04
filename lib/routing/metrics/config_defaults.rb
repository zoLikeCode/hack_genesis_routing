# frozen_string_literal: true

module Routing
  module Metrics
    module ConfigDefaults
      HASH = {
        "window" => { "max_observations" => 50, "recent_observations" => 10 },
        "smoothing" => {
          "prior_strength" => 10.0,
          "timeout_prior" => 0.10,
          "timeout_prior_strength" => 5.0,
          "segment_min_size" => 5,
          "segment_confidence_strength" => 10.0
        },
        "combination" => "weighted_sum",
        "components" => {
          "approval_rate" => { "enabled" => true, "weight" => 0.40 },
          "availability" => { "enabled" => true, "weight" => 0.25 },
          "acceptance" => { "enabled" => true, "weight" => 0.15 },
          "latency" => { "enabled" => true, "weight" => 0.20, "bad_p90_sec" => 600.0 }
        },
        "multipliers" => {
          "health" => {
            "enabled" => true,
            "floor" => 0.25,
            "exponent" => 1.0,
            "availability_weight" => 0.60,
            "acceptance_weight" => 0.40
          }
        }
      }.freeze
    end
  end
end
