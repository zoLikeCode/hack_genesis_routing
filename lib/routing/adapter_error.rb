# frozen_string_literal: true

module Routing
  class AdapterError < Error
    KINDS = %i[definite_miss ambiguous].freeze

    attr_reader :kind, :cause

    def initialize(message, kind:, cause: nil)
      Routing.assert(KINDS.include?(kind), "unknown adapter error kind #{kind}")
      super(message)
      @kind = kind
      @cause = cause
    end

    def definite_miss?
      kind == :definite_miss
    end

    def ambiguous?
      kind == :ambiguous
    end

    def self.from(error, reservation:)
      Routing.assert(error.is_a?(Exception), "adapter error requires an Exception")
      Routing.assert(reservation.is_a?(Reservation), "adapter error requires a Reservation")
      kind = reservation.dispatching? || reservation.timed_out? ? :ambiguous : :definite_miss
      new(error.message, kind: kind, cause: error)
    end
  end
end
