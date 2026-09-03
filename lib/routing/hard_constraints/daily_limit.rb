# frozen_string_literal: true

module Routing
  module HardConstraints
    class DailyLimit
      def self.call(provider, operation)
        limit = provider.daily_amount_limit
        return Result.ok if limit.nil?

        projected = provider.daily_approved_amount + operation.amount
        return Result.ok if projected <= limit

        Result.skip(
          Reasons::DAILY_LIMIT_EXCEEDED,
          "#{projected} > daily_amount_limit #{limit}"
        )
      end
    end
  end
end
