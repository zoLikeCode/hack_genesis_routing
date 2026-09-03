# frozen_string_literal: true

module Routing
  module HardConstraints
    class Result
      attr_reader :reason, :details

      def initialize(passed, reason, details)
        @ok = passed
        @reason = reason
        @details = details
      end

      OK = new(true, nil, nil).freeze

      def self.ok
        OK
      end

      def self.skip(reason, details = nil)
        Routing.assert(reason.is_a?(String) && !reason.empty?, "skip reason required")
        new(false, reason, details)
      end

      def ok?
        @ok
      end

      def skipped?
        !@ok
      end
    end
  end
end
