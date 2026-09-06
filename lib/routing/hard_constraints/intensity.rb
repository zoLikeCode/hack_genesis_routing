# frozen_string_literal: true

module Routing
  module HardConstraints
    class Intensity
      def self.call(provider, operation, at: nil)
        limit = provider.requests_per_minute_limit
        return Result.ok if limit.nil?

        at ||= operation.created_at
        raise InvalidInputError, "created_at required for intensity check" if at.nil?

        count = provider.request_count_at(at)
        return Result.ok if count < limit

        Result.skip(
          Reasons::RATE_LIMIT_EXCEEDED,
          "#{count} >= requests_per_minute_limit #{limit}"
        )
      end
    end
  end
end
