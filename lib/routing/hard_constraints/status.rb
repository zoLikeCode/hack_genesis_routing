# frozen_string_literal: true

module Routing
  module HardConstraints
    class Status
      ACTIVE = "active"

      def self.call(provider, _operation)
        return Result.ok if provider.status == ACTIVE

        Result.skip(Reasons::PROVIDER_INACTIVE, "#{provider.status} != #{ACTIVE}")
      end
    end
  end
end
