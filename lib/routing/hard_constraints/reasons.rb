# frozen_string_literal: true

module Routing
  module HardConstraints
    module Reasons
      PROVIDER_INACTIVE = "provider_inactive"
      AMOUNT_BELOW_MINIMUM = "amount_below_minimum"
      AMOUNT_EXCEEDS_LIMIT = "amount_exceeds_limit"
      DAILY_LIMIT_EXCEEDED = "daily_limit_exceeded"
      IN_PROGRESS_COUNT_EXCEEDED = "in_progress_count_exceeded"
      IN_PROGRESS_AMOUNT_EXCEEDED = "in_progress_amount_exceeded"
      BANK_NOT_IN_LIST = "bank_not_in_list"
      BANK_EXCLUDED = "bank_excluded"
      NEGATIVE_MARGIN = "negative_margin"
      NO_REQUISITES = "no_requisites"
      RATE_LIMIT_EXCEEDED = "rate_limit_exceeded"
      NO_DISPATCH_SLOT = "no_dispatch_slot"
      CIRCUIT_BREAKER_OPEN = "circuit_breaker_open"

      DURABLE = [
        PROVIDER_INACTIVE,
        AMOUNT_BELOW_MINIMUM,
        AMOUNT_EXCEEDS_LIMIT,
        BANK_NOT_IN_LIST,
        BANK_EXCLUDED,
        NEGATIVE_MARGIN
      ].freeze

      CAPACITY = [
        DAILY_LIMIT_EXCEEDED,
        IN_PROGRESS_COUNT_EXCEEDED,
        IN_PROGRESS_AMOUNT_EXCEEDED,
        NO_REQUISITES,
        RATE_LIMIT_EXCEEDED,
        NO_DISPATCH_SLOT,
        CIRCUIT_BREAKER_OPEN
      ].freeze

      def self.capacity?(reason)
        CAPACITY.include?(reason)
      end

      def self.waitable?(reason)
        capacity?(reason) && reason != CIRCUIT_BREAKER_OPEN
      end

      def self.durable?(reason)
        DURABLE.include?(reason)
      end
    end
  end
end
