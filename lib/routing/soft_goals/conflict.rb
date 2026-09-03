# frozen_string_literal: true

module Routing
  module SoftGoals
    class Conflict
      attr_reader :kind, :provider, :details

      def initialize(kind:, provider: nil, details: nil)
        Routing.assert(kind.is_a?(String) && !kind.empty?, "conflict kind required")
        @kind = kind
        @provider = provider
        @details = details
      end
    end
  end
end
