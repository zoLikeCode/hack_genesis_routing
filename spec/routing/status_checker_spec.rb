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

  it "keeps an unresolved reservation for manual review", :aggregate_failures do
    checker, state, reservation, now = build_checker(
      statuses: %w[pending pending],
      config: status_config("max_attempts" => 2)
    )
    task = checker.schedule(reservation, timed_out_at: now)

    checker.run_due(now: now + 5)
    checker.run_due(now: now + 15)

    expect(task).to have_attributes(status: "manual_review", attempts: 2, last_result: "pending")
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

    expect(task).to have_attributes(status: "manual_review", attempts: 1, last_result: "error")
    expect(task.last_error).to include("IOError: status endpoint unavailable")
    expect(reservation.status).to eq("timed_out")
    expect(state.providers.fetch("vipay").in_progress_count).to eq(1)
  end

  def build_checker(statuses:, config: status_config)
    provider = build_provider
    pool = Routing::ProviderPool.new([provider])
    state = Routing::RuntimeState.new(pool)
    operation = build_operation
    reservation = state.try_reserve!(provider, operation, expected_revision: state.snapshot.revision).reservation
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
