# frozen_string_literal: true

module Routing
  class StatusChecker
    TERMINAL_RESULTS = %w[approved rejected cancelled].freeze
    RETRY_RESULTS = %w[pending processing expired unknown].freeze

    attr_reader :state, :providers

    def initialize(state:, providers:, client:, config:)
      Routing.assert(state.is_a?(RuntimeState), "status checker requires RuntimeState")
      Routing.assert(providers.is_a?(ProviderPool), "status checker requires ProviderPool")
      Routing.assert(config.respond_to?(:to_h), "status check config must be a Hash")
      @state = state
      @providers = providers
      @client = client
      @config = config.to_h
      @tasks = {}
      @mutex = Mutex.new
    end

    def schedule(reservation, timed_out_at:)
      return unless enabled?

      Routing.assert(reservation.is_a?(Reservation), "status check requires a Reservation")
      Routing.assert(reservation.timed_out?, "status check requires a timed-out reservation")
      Routing.assert(timed_out_at.is_a?(Time), "timed_out_at must be Time")
      @mutex.synchronize do
        @tasks[reservation.idempotency_key] ||= StatusCheckTask.new(
          reservation: reservation,
          next_check_at: timed_out_at + initial_delay
        )
      end
    end

    def run_due(now:)
      Routing.assert(now.is_a?(Time), "status check time must be Time")
      return empty_run unless enabled?

      due = claim_due(now)
      result = empty_run.merge("checked" => due.size)
      due.each { |task| process(task, now, result) }
      result.freeze
    end

    def tasks
      @mutex.synchronize { @tasks.values.dup.freeze }
    end

    def next_check_at
      @mutex.synchronize do
        @tasks.values.select(&:scheduled?).filter_map(&:next_check_at).min
      end
    end

    def summary
      snapshot = tasks
      counts = snapshot.map(&:status).tally
      {
        "scheduled" => counts.fetch("scheduled", 0),
        "checking" => counts.fetch("checking", 0),
        "resolved" => counts.fetch("resolved", 0),
        "manual_review" => counts.fetch("manual_review", 0),
        "tasks" => snapshot.map(&:to_h)
      }
    end

    private

    def enabled?
      @config.fetch("enabled")
    end

    def initial_delay
      @config.fetch("initial_delay_sec")
    end

    def retry_delays
      @config.fetch("retry_delays_sec")
    end

    def max_attempts
      @config.fetch("max_attempts")
    end

    def empty_run
      { "checked" => 0, "resolved" => 0, "rescheduled" => 0, "manual_review" => 0 }
    end

    def claim_due(now)
      @mutex.synchronize do
        @tasks.values.select { |task| task.due?(now) }.each(&:start!)
      end
    end

    def process(task, now, totals)
      status = ProviderStatusInvoker.call(
        client: @client,
        provider: providers.fetch(task.reservation.provider_name),
        task: task
      )
      return resolve(task, status, totals) if TERMINAL_RESULTS.include?(status)

      Routing.assert(RETRY_RESULTS.include?(status), "unsupported provider status #{status}")
      retry_or_escalate(task, now, status, totals)
    rescue StandardError => e
      retry_or_escalate(task, now, "error", totals, error: "#{e.class}: #{e.message}")
    end

    def resolve(task, status, totals)
      reservation = state.resolve_timeout!(
        operation_id: task.reservation.operation_id,
        provider_name: task.reservation.provider_name,
        result: status
      )
      unless expected_settlement(status) == reservation.status
        return resolve_conflict(task, status, reservation, totals)
      end

      @mutex.synchronize { task.resolve!(result: reservation.status) }
      totals["resolved"] += 1
    end

    def resolve_conflict(task, status, reservation, totals)
      error = "status-check returned #{status}, but reservation is already #{reservation.status}"
      @mutex.synchronize { task.manual_review!(result: status, error: error) }
      totals["manual_review"] += 1
    end

    def expected_settlement(status)
      status == "approved" ? "approved" : "rejected"
    end

    def retry_or_escalate(task, now, status, totals, error: nil)
      if task.attempts >= max_attempts
        @mutex.synchronize { task.manual_review!(result: status, error: error) }
        totals["manual_review"] += 1
        return
      end

      delay = retry_delays.fetch([task.attempts - 1, retry_delays.size - 1].min)
      @mutex.synchronize { task.reschedule!(at: now + delay, result: status, error: error) }
      totals["rescheduled"] += 1
    end
  end
end
