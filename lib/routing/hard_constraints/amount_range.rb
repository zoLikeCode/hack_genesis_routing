# frozen_string_literal: true

module Routing
  module HardConstraints
    class AmountRange
      def self.call(provider, operation)
        amount = operation.amount
        min = provider.limit_amount_min
        max = provider.limit_amount_max

        if !min.nil? && amount < min
          return Result.skip(Reasons::AMOUNT_BELOW_MINIMUM, "#{amount} < limit_amount_min #{min}")
        end
        if !max.nil? && amount > max
          return Result.skip(Reasons::AMOUNT_EXCEEDS_LIMIT, "#{amount} > limit_amount_max #{max}")
        end

        Result.ok
      end
    end
  end
end
