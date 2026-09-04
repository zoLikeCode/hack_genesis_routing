# frozen_string_literal: true

module Routing
  class Reservation
    ACTIVE_STATUSES = %w[pending timed_out].freeze
    TERMINAL_STATUSES = %w[approved rejected].freeze
    STATUSES = (ACTIVE_STATUSES + TERMINAL_STATUSES).freeze

    attr_reader :idempotency_key, :operation_id, :provider_name, :amount, :created_at, :status

    def initialize(operation:, provider_name:)
      Routing.assert(operation.is_a?(Operation), "reservation requires Routing::Operation")
      Routing.assert(provider_name.is_a?(String) && !provider_name.empty?, "provider name required")
      @operation_id = operation.id
      @provider_name = provider_name
      @amount = operation.amount
      @created_at = operation.created_at
      @idempotency_key = "#{operation.id}:#{provider_name}"
      @status = "pending"
    end

    def active?
      ACTIVE_STATUSES.include?(status)
    end

    def timed_out?
      status == "timed_out"
    end

    def mark_timed_out!
      transition!("timed_out", from: "pending")
    end

    def approve!
      transition!("approved", from: ACTIVE_STATUSES)
    end

    def reject!
      transition!("rejected", from: ACTIVE_STATUSES)
    end

    private

    def transition!(next_status, from:)
      allowed = Array(from)
      Routing.assert(allowed.include?(status), "cannot move reservation from #{status} to #{next_status}")
      Routing.assert(STATUSES.include?(next_status), "unknown reservation status #{next_status}")
      @status = next_status
      self
    end
  end
end
