# frozen_string_literal: true

module Routing
  module SoftGoals
    GOALS = [
      CountShare,
      VolumeShare,
      Conversion,
      CascadePriority,
      FinancialObligation
    ].freeze

    def self.deficit_score(target, actual)
      return 0.0 if target.nil?

      ((target.to_f - actual.to_f) / 100.0).clamp(-1.0, 1.0)
    end
  end
end
