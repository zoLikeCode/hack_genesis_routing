# frozen_string_literal: true

require "time"

module Routing
  class StatusCheckTask
    ACTIVE_STATUSES = %w[scheduled checking].freeze
    TERMINAL_STATUSES = %w[resolved manual_review].freeze
    STATUSES = (ACTIVE_STATUSES + TERMINAL_STATUSES).freeze

    attr_reader :reservation, :attempts, :next_check_at, :last_result, :last_error, :status

    def initialize(reservation:, next_check_at:)
      Routing.assert(reservation.is_a?(Reservation), "status check requires a Reservation")
      Routing.assert(reservation.timed_out?, "status check requires a timed-out reservation")
      Routing.assert(next_check_at.is_a?(Time), "next_check_at must be Time")
      @reservation = reservation
      @next_check_at = next_check_at
      @attempts = 0
      @last_result = nil
      @last_error = nil
      @status = "scheduled"
    end

    def idempotency_key
      reservation.idempotency_key
    end

    def due?(now)
      status == "scheduled" && next_check_at <= now
    end

    def start!
      transition!("checking", from: "scheduled")
      @attempts += 1
      self
    end

    def reschedule!(at:, result:, error: nil)
      Routing.assert(at.is_a?(Time), "next status check time must be Time")
      transition!("scheduled", from: "checking")
      @next_check_at = at
      @last_result = result
      @last_error = error
      self
    end

    def resolve!(result:)
      transition!("resolved", from: "checking")
      @last_result = result
      @last_error = nil
      @next_check_at = nil
      self
    end

    def manual_review!(result:, error: nil)
      transition!("manual_review", from: "checking")
      @last_result = result
      @last_error = error
      @next_check_at = nil
      self
    end

    def to_h
      {
        "operation_id" => reservation.operation_id,
        "provider" => reservation.provider_name,
        "idempotency_key" => idempotency_key,
        "status" => status,
        "attempts" => attempts,
        "next_check_at" => next_check_at&.iso8601,
        "last_result" => last_result,
        "last_error" => last_error
      }
    end

    private

    def transition!(next_status, from:)
      Routing.assert(STATUSES.include?(next_status), "unknown status check state #{next_status}")
      Routing.assert(Array(from).include?(status), "cannot move status check from #{status} to #{next_status}")
      @status = next_status
    end
  end
end
