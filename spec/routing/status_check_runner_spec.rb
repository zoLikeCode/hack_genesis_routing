# frozen_string_literal: true

require "timeout"

RSpec.describe Routing::StatusCheckRunner do
  it "drains scheduled checks with logical time", :aggregate_failures do
    checker, reservation, now = build_checker(statuses: %w[pending approved])
    checker.schedule(reservation, timed_out_at: now)

    totals = described_class.new(checker: checker).drain

    expect(totals).to include("checked" => 2, "rescheduled" => 1, "resolved" => 1)
    expect(reservation.status).to eq("approved")
    expect(checker.tasks.first).to have_attributes(status: "resolved", attempts: 2)
  end

  it "stops at reconciliation while keeping the reservation", :aggregate_failures do
    checker, reservation, now = build_checker(statuses: %w[pending pending], max_attempts: 2)
    checker.schedule(reservation, timed_out_at: now)

    totals = described_class.new(checker: checker).drain

    expect(totals).to include("checked" => 2, "rescheduled" => 1, "reconciliation_pending" => 1)
    expect(reservation.status).to eq("timed_out")
    expect(checker.tasks.first.status).to eq("reconciliation_pending")
  end

  it "runs a due check without waiting for another operation", :aggregate_failures do
    checker, reservation, = build_checker(statuses: %w[approved], initial_delay: 0)
    runner = described_class.new(checker: checker).start

    runner.schedule(reservation, timed_out_at: Time.now)
    Timeout.timeout(1) { Thread.pass until reservation.status == "approved" }

    expect(reservation.status).to eq("approved")
    expect(checker.tasks.first.status).to eq("resolved")
    expect(runner).to be_running
  ensure
    runner&.stop
  end

  it "performs exactly five checks when the provider never reaches a terminal status", :aggregate_failures do
    checker, reservation, now = build_checker(statuses: Array.new(5, "pending"), max_attempts: 5)
    checker.schedule(reservation, timed_out_at: now)

    totals = described_class.new(checker: checker).drain

    expect(totals).to include(
      "checked" => 5, "rescheduled" => 4, "reconciliation_pending" => 1, "resolved" => 0
    )
    expect(checker.tasks.first).to have_attributes(
      status: "reconciliation_pending", attempts: 5, next_check_at: nil
    )
    expect(reservation.status).to eq("timed_out")
  end

  def build_checker(statuses:, max_attempts: 3, initial_delay: 5)
    provider = build_provider
    pool = Routing::ProviderPool.new([provider])
    state = Routing::RuntimeState.new(pool)
    operation = build_operation
    reservation = state.try_reserve!(provider, operation, expected_revision: state.snapshot.revision).reservation
    state.mark_dispatching!(reservation, at: operation.created_at)
    state.mark_timeout!(reservation)
    checker = Routing::StatusChecker.new(
      state: state,
      providers: pool,
      client: status_client(statuses),
      config: status_config(max_attempts, initial_delay)
    )
    [checker, reservation, operation.created_at]
  end

  def status_client(statuses)
    queue = statuses.dup
    Object.new.tap do |client|
      client.define_singleton_method(:status) { |*, **| { result: queue.shift || "pending" } }
    end
  end

  def status_config(max_attempts, initial_delay)
    {
      "enabled" => true,
      "initial_delay_sec" => initial_delay,
      "retry_delays_sec" => [10],
      "max_attempts" => max_attempts
    }
  end
end
