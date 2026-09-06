# frozen_string_literal: true

RSpec.describe Routing::StatusChecker do
  it "retries pending checks and commits a later approval", :aggregate_failures do
    checker, state, reservation, now = build_checker(statuses: %w[pending approved])
    task = checker.schedule(reservation, timed_out_at: now)

    expect(checker.run_due(now: now + 4).fetch("checked")).to eq(0)
    expect(checker.run_due(now: now + 5)).to include("checked" => 1, "rescheduled" => 1)
    expect(task).to have_attributes(status: "scheduled", attempts: 1, next_check_at: now + 15)
    expect(checker.run_due(now: now + 14).fetch("checked")).to eq(0)
    expect(checker.run_due(now: now + 15)).to include("checked" => 1, "resolved" => 1)
    expect(task).to have_attributes(status: "resolved", attempts: 2, last_result: "approved")
    expect(reservation.status).to eq("approved")
    expect(state.snapshot.soft_goals.total_count).to eq(1)
  end

  it "releases current counters after a cancellation", :aggregate_failures do
    checker, state, reservation, now = build_checker(statuses: %w[cancelled])
    checker.schedule(reservation, timed_out_at: now)
    checker.run_due(now: now + 5)

    expect(reservation.status).to eq("rejected")
    expect(state.snapshot.soft_goals.total_count).to eq(0)
    expect(state.providers.fetch("vipay")).to have_attributes(in_progress_count: 0, daily_reserved_amount: 0)
  end

  it "moves an unresolved reservation to reconciliation after the retry budget", :aggregate_failures do
    checker, state, reservation, now = build_checker(
      statuses: %w[pending pending],
      config: status_config("max_attempts" => 2)
    )
    task = checker.schedule(reservation, timed_out_at: now)

    checker.run_due(now: now + 5)
    checker.run_due(now: now + 15)

    expect(task).to have_attributes(
      status: "reconciliation_pending", attempts: 2, last_result: "pending", next_check_at: nil
    )
    expect(reservation.status).to eq("timed_out")
    expect(state.providers.fetch("vipay").in_progress_count).to eq(1)
  end

  it "deduplicates status-check tasks by idempotency key", :aggregate_failures do
    checker, _state, reservation, now = build_checker(statuses: [])
    first = checker.schedule(reservation, timed_out_at: now)
    second = checker.schedule(reservation, timed_out_at: now + 1)

    expect(second).to equal(first)
    expect(checker.tasks.size).to eq(1)
  end

  it "keeps the reservation when the provider status endpoint fails", :aggregate_failures do
    checker, state, reservation, now = build_checker(statuses: [], config: status_config("max_attempts" => 1))
    checker.instance_variable_set(:@client, failing_status_client)
    task = checker.schedule(reservation, timed_out_at: now)

    checker.run_due(now: now + 5)

    expect(task).to have_attributes(
      status: "reconciliation_pending", attempts: 1, last_result: "error", next_check_at: nil
    )
    expect(task.last_error).to include("IOError: status endpoint unavailable")
    expect(reservation.status).to eq("timed_out")
    expect(state.providers.fetch("vipay").in_progress_count).to eq(1)
  end

  it "records a conflicting terminal result for reconciliation", :aggregate_failures do
    checker, state, reservation, now = build_checker(statuses: %w[cancelled])
    task = checker.schedule(reservation, timed_out_at: now)
    state.resolve_timeout!(
      operation_id: reservation.operation_id,
      provider_name: reservation.provider_name,
      result: "approved"
    )

    result = checker.run_due(now: now + 5)

    expect(result).to include("checked" => 1, "reconciliation_pending" => 1, "resolved" => 0)
    expect(task).to have_attributes(status: "reconciliation_pending", last_result: "cancelled")
    expect(task.last_error).to include("reservation is already approved")
    expect(reservation.status).to eq("approved")
  end

  it "claims only as many due tasks as the worker pool can accept", :aggregate_failures do
    checker, state, first, now = build_checker(statuses: [])
    second_operation = build_operation(operation_id: "op_second")
    second = state.try_reserve!(
      state.providers.fetch("vipay"), second_operation, expected_revision: state.snapshot.revision
    ).reservation
    state.mark_dispatching!(second, at: now)
    state.mark_timeout!(second)
    checker.schedule(first, timed_out_at: now)
    checker.schedule(second, timed_out_at: now)

    claimed = checker.take_due(now + 5, limit: 1)

    expect(claimed.size).to eq(1)
    expect(checker.tasks.map(&:status).tally).to eq("checking" => 1, "scheduled" => 1)
  end

  def build_checker(statuses:, config: status_config)
    provider = build_provider
    pool = Routing::ProviderPool.new([provider])
    state = Routing::RuntimeState.new(pool)
    operation = build_operation
    reservation = state.try_reserve!(provider, operation, expected_revision: state.snapshot.revision).reservation
    state.mark_dispatching!(reservation, at: operation.created_at)
    state.mark_timeout!(reservation)
    checker = described_class.new(
      state: state,
      providers: pool,
      client: status_client(statuses),
      config: config
    )
    [checker, state, reservation, operation.created_at]
  end

  def status_client(statuses)
    queue = statuses.dup
    Object.new.tap do |client|
      client.define_singleton_method(:status) do |_provider, operation_id:, idempotency_key:|
        raise "missing status context" if operation_id.empty? || idempotency_key.empty?

        { result: queue.shift || "pending" }
      end
    end
  end

  def status_config(overrides = {})
    {
      "enabled" => true,
      "initial_delay_sec" => 5,
      "retry_delays_sec" => [10],
      "max_attempts" => 3
    }.merge(overrides)
  end

  def failing_status_client
    Object.new.tap do |client|
      client.define_singleton_method(:status) { |*, **| raise IOError, "status endpoint unavailable" }
    end
  end
end
