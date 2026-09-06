# frozen_string_literal: true

module Routing
  class Reservation
    ACTIVE_STATUSES = %w[reserved dispatching timed_out].freeze
    TERMINAL_STATUSES = %w[approved rejected].freeze
    STATUSES = (ACTIVE_STATUSES + TERMINAL_STATUSES).freeze

    attr_reader :idempotency_key, :operation_id, :provider_name, :amount, :created_at, :status, :operation,
                :admission_sequence

    def initialize(operation:, provider_name:)
      Routing.assert(operation.is_a?(Operation), "reservation requires Routing::Operation")
      Routing.assert(provider_name.is_a?(String) && !provider_name.empty?, "provider name required")
      @operation = operation
      @operation_id = operation.id
      @provider_name = provider_name
      @amount = operation.amount
      @created_at = operation.created_at
      @idempotency_key = "#{operation.id}:#{provider_name}"
      @status = "reserved"
      @admission_sequence = nil
    end

    def active?
      ACTIVE_STATUSES.include?(status)
    end

    def reserved?
      status == "reserved"
    end

    def dispatching?
      status == "dispatching"
    end

    def timed_out?
      status == "timed_out"
    end

    def mark_dispatching!(admission_sequence:)
      Routing.assert(admission_sequence.is_a?(Integer) && admission_sequence.positive?,
                     "admission_sequence must be a positive integer")
      transition!("dispatching", from: "reserved")
      @admission_sequence = admission_sequence
      self
    end

    def mark_timed_out!
      transition!("timed_out", from: "dispatching")
    end

    def approve!
      transition!("approved", from: %w[dispatching timed_out])
    end

    def reject!
      transition!("rejected", from: ACTIVE_STATUSES)
    end

    def to_h
      {
        "idempotency_key" => idempotency_key,
        "operation_id" => operation_id,
        "provider" => provider_name,
        "amount" => amount,
        "created_at" => created_at&.iso8601,
        "status" => status,
        "admission_sequence" => admission_sequence,
        "operation" => operation.to_h
      }
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
