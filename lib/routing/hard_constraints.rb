# frozen_string_literal: true

module Routing
  module HardConstraints
    CHECKS = [
      Status,
      AmountRange,
      DailyLimit,
      InProgress,
      BankFilter,
      Margin,
      Requisites,
      Intensity
    ].freeze
  end
end
