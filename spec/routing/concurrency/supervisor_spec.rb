# frozen_string_literal: true

require "async"

RSpec.describe Routing::Concurrency::Supervisor do
  it "overlaps two in-flight payouts on different providers", :aggregate_failures do
    started = []
    route_concurrent(sleep_client(0.15, started), two_provider_pool, two_operations)

    expect(started.size).to eq(2)
    starts = started.map(&:last)
    expect(starts.max - starts.min).to be < 0.08
  end

  it "cannot reserve the last payout slot twice" do
    provider = build_provider(in_progress_count_limit: 1)
    pool = Routing::ProviderPool.new([provider, fallback_provider])
    decisions = route_concurrent(sleep_client(0.05, []), pool, two_operations)

    expect(decisions.map(&:selected_provider)).to contain_exactly("vipay", "spacepayments")
  end

  it "records no_dispatch_slot without marking the provider attempted", :aggregate_failures do
    pool = Routing::ProviderPool.new([build_provider, payflow_provider, fallback_provider])
    policy = concurrent_policy("max_workers_per_provider" => 1)
    decisions = route_concurrent(sleep_client(0.05, []), pool, two_operations, policy)
    skipped = decisions.flat_map(&:attempts).select { |attempt| attempt.reason == "no_dispatch_slot" }

    expect(skipped.map(&:decision).uniq).to eq(["skipped"])
    expect(decisions.map(&:selected_provider)).to include("payflow")
  end

  it "parks overflow ops instead of raising InvalidInputError" do
    pool = Routing::ProviderPool.new(
      [
        build_provider(in_progress_count_limit: 1),
        payflow_provider(in_progress_count_limit: 1),
        fallback_provider(in_progress_count_limit: 1)
      ]
    )
    operations = two_operations + [
      build_operation(operation_id: "op_c", created_at: "2026-07-30T09:07:00+03:00"),
      build_operation(operation_id: "op_d", created_at: "2026-07-30T09:08:00+03:00")
    ]

    expect { route_concurrent(sleep_client(0.05, []), pool, operations) }.not_to raise_error
  end

  it "does not start a second payout after timeout", :aggregate_failures do
    calls = []
    client = timeout_client(calls, status: "approved")
    decisions = route_concurrent(client, two_provider_pool, [build_operation])

    expect(calls).to eq(["vipay"])
    expect(decisions.first).to have_attributes(selected_provider: "vipay", simulated_result: "approved")
    expect(decisions.first).to be_final
  end

  it "changes selected_provider after a late status rejection", :aggregate_failures do
    calls = []
    client = timeout_client(calls, status: "rejected")
    decisions = route_concurrent(client, two_provider_pool, [build_operation])

    expect(decisions.first.selected_provider).to eq("payflow")
    expect(calls).to eq(%w[vipay payflow])
  end

  it "emits results in inbound order" do
    decisions = route_concurrent(sleep_client(0.01, []), two_provider_pool, two_operations)

    expect(decisions.map(&:operation_id)).to eq(%w[op_a op_b])
  end

  it "bounds concurrent status checks without losing due tasks", :aggregate_failures do
    running = 0
    peak = 0
    client = timeout_client([], status: "approved")
    client.define_singleton_method(:status) do |*, **|
      running += 1
      peak = [peak, running].max
      Async::Task.current.sleep(0.03)
      running -= 1
      { result: "approved" }
    end
    decisions = route_concurrent(
      client, two_provider_pool, two_operations,
      concurrent_policy("status_worker_limit" => 1)
    )

    expect(peak).to eq(1)
    expect(decisions).to all(be_final)
    expect(decisions.map(&:simulated_result)).to eq(%w[approved approved])
  end

  it "supports the thread-pool executor end to end" do
    decisions = route_concurrent(
      sleep_client(0.01, []), two_provider_pool, two_operations,
      concurrent_policy("executor" => "thread_pool")
    )

    expect(decisions).to all(be_final)
  end

  it "uses live dispatch time for the RPM limit" do
    provider = build_provider(requests_per_minute_limit: 1)
    pool = Routing::ProviderPool.new([provider, fallback_provider])
    decisions = route_concurrent(sleep_client(0.03, []), pool, two_operations)

    expect(decisions.map(&:selected_provider)).to contain_exactly("vipay", "spacepayments")
  end

  it "fails promptly when static limits make every provider unroutable" do
    pool = Routing::ProviderPool.new(
      [build_provider(daily_amount_limit: 0), fallback_provider(daily_amount_limit: 0)]
    )

    expect do
      route_concurrent(sleep_client(0.01, []), pool, [build_operation])
    end.to raise_error(Routing::InvalidInputError, /cannot be routed/)
  end

  it "classifies a transport failure as ambiguous and reconciles by status", :aggregate_failures do
    client = timeout_client([], status: "approved")
    client.define_singleton_method(:call) { |*, **| raise IOError, "HTTP 500" }
    decisions = route_concurrent(client, two_provider_pool, [build_operation])

    expect(decisions.first).to have_attributes(simulated_result: "approved", selected_provider: "vipay")
    expect(decisions.first).to be_final
  end

  it "does not emit a provisional decision after reconciliation is exhausted" do
    client = timeout_client([], status: "pending")
    policy = Routing::Policy.new(
      "fallback_provider" => "spacepayments",
      "strategies" => default_strategy_weights,
      "status_check" => {
        "enabled" => true, "initial_delay_sec" => 0,
        "retry_delays_sec" => [0], "max_attempts" => 1
      },
      "concurrency" => { "enabled" => true }
    )

    expect do
      route_concurrent(client, two_provider_pool, [build_operation], policy)
    end.to raise_error(Routing::InvalidInputError, /reconciliation_pending: op_test/)
  end

  it "does not wait forever for capacity held by exhausted reconciliation" do
    client = timeout_client([], status: "pending")
    policy = Routing::Policy.new(
      "fallback_provider" => "spacepayments",
      "strategies" => default_strategy_weights,
      "status_check" => {
        "enabled" => true, "initial_delay_sec" => 0,
        "retry_delays_sec" => [0], "max_attempts" => 1
      },
      "concurrency" => { "enabled" => true }
    )
    pool = Routing::ProviderPool.new(
      [build_provider(in_progress_count_limit: 1), fallback_provider(daily_amount_limit: 0)]
    )

    expect do
      route_concurrent(client, pool, two_operations, policy)
    end.to raise_error(Routing::InvalidInputError, /cannot be routed/)
  end

  def route_concurrent(client, pool, operations, policy = build_policy)
    Routing::Engine.call(
      operations: operations, providers: pool, policy: policy, simulator: client, concurrent: true
    )
  end

  def concurrent_policy(overrides = {})
    Routing::Policy.new(
      "fallback_provider" => "spacepayments",
      "strategies" => default_strategy_weights,
      "concurrency" => { "enabled" => true }.merge(overrides)
    )
  end

  def sleep_client(delay, started)
    Object.new.tap do |client|
      client.define_singleton_method(:call) do |provider, **|
        started << [provider.name, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
        Async::Task.current.sleep(delay)
        { result: "approved", latency_sec: delay }
      end
      client.define_singleton_method(:status) { |*, **| { result: "approved" } }
    end
  end

  def timeout_client(calls, status: "approved")
    Object.new.tap do |client|
      client.define_singleton_method(:call) do |provider, **|
        calls << provider.name
        result = status == "rejected" && calls.size > 1 ? "approved" : "expired"
        { result: result, latency_sec: 0 }
      end
      client.define_singleton_method(:status) { |*, **| { result: status } }
    end
  end

  def two_operations
    [
      build_operation(operation_id: "op_a"),
      build_operation(operation_id: "op_b", created_at: "2026-07-30T09:06:00+03:00")
    ]
  end

  def two_provider_pool
    Routing::ProviderPool.new([build_provider, payflow_provider, fallback_provider])
  end

  def payflow_provider(**overrides)
    build_provider(
      payment_system: "payflow", traffic_percentage: 35, priority: 2,
      conversion_24h: 0.91, banks: %w[sberbank alfa], **overrides
    )
  end

  def fallback_provider(**overrides)
    build_provider(
      payment_system: "spacepayments", traffic_percentage: 0, limit_amount_min: nil,
      limit_amount_max: nil, daily_amount_limit: nil, in_progress_count_limit: nil,
      in_progress_amount_limit: nil, banks: [], conversion_24h: 1.0, **overrides
    )
  end
end
