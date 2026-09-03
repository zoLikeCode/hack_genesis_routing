# frozen_string_literal: true

module Routing
  module HardConstraints
    class Requisites
      def self.call(provider, _operation)
        return Result.ok unless provider.available_requisites.zero?

        Result.skip(Reasons::NO_REQUISITES, "available_requisites == 0")
      end
    end
  end
end
