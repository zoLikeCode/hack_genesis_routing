# frozen_string_literal: true

module Routing
  module HardConstraints
    class InProgress
      def self.call(provider, operation)
        count_skip = count_result(provider)
        return count_skip if count_skip.skipped?

        amount_result(provider, operation)
      end

      def self.count_result(provider)
        limit = provider.in_progress_count_limit
        return Result.ok if limit.nil?

        projected = provider.in_progress_count + 1
        return Result.ok if projected <= limit

        Result.skip(
          Reasons::IN_PROGRESS_COUNT_EXCEEDED,
          "#{projected} > in_progress_count_limit #{limit}"
        )
      end
      private_class_method :count_result

      def self.amount_result(provider, operation)
        limit = provider.in_progress_amount_limit
        return Result.ok if limit.nil?

        projected = provider.in_progress_amount + operation.amount
        return Result.ok if projected <= limit

        Result.skip(
          Reasons::IN_PROGRESS_AMOUNT_EXCEEDED,
          "#{projected} > in_progress_amount_limit #{limit}"
        )
      end
      private_class_method :amount_result
    end
  end
end
