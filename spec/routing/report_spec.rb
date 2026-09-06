# frozen_string_literal: true

RSpec.describe Routing::Report do
  subject(:report) do
    described_class.call(decisions: [decision], operations: [build_operation], providers: pool, policy: build_policy)
  end

  let(:pool) { Routing::ProviderPool.new([vipay, payflow, fallback]) }
  let(:vipay) { build_provider(daily_approved_amount: 4_200_000) }
  let(:payflow) do
    build_provider(payment_system: "payflow", traffic_percentage: 35, priority: 2, daily_amount_limit: 3_000_000)
  end
  let(:fallback) do
    build_provider(payment_system: "spacepayments", traffic_percentage: 0, daily_amount_limit: nil, banks: [])
  end
  let(:decision) do
    Routing::Decision.new(
      operation_id: "op_test",
      selected_provider: "vipay",
      attempts: [
        Routing::HardConstraints::Attempt.new(provider: "payflow", decision: "skipped", reason: "bank_not_in_list"),
        Routing::HardConstraints::Attempt.new(provider: "vipay", decision: "selected", reason: "highest_soft_score")
      ],
      simulated_result: "approved",
      latency_sec: 30
    )
  end

  it "includes the required report keys" do
    expect(report.keys).to include(
      "period", "total_operations", "distribution", "outcomes", "history_baseline",
      "provider_metrics", "conversion_backtest", "routing_profiles", "unassigned_operations", "rejected_operations",
      "skip_reasons", "projected_daily_utilization", "recommendations"
    )
  end

  it "sets period from the first operation timestamp" do
    expect(report.fetch("period")).to eq("2026-07-30")
  end

  it "tallies skip reasons" do
    expect(report.fetch("skip_reasons")).to eq("bank_not_in_list" => 1)
  end

  it "recommends reducing traffic when utilization is high" do
    expect(report.fetch("recommendations").join).to include("traffic_percentage")
  end

  it "recommends expanding banks when bank_not_in_list dominates skips" do
    expect(report.fetch("recommendations").join).to include("expand banks")
  end

  it "does not count an explicitly rejected provider as accepted traffic", :aggregate_failures do
    rejected = Routing::Decision.new(
      operation_id: "op_rejected",
      selected_provider: "vipay",
      attempts: [],
      simulated_result: "rejected",
      latency_sec: 10
    )
    rejected_report = described_class.call(
      decisions: [rejected],
      operations: [build_operation],
      providers: pool,
      policy: build_policy
    )

    expect(rejected_report.dig("distribution", "vipay", "count")).to eq(0)
    expect(rejected_report.fetch("rejected_operations")).to eq(1)
    expect(rejected_report.fetch("unassigned_operations")).to eq(0)
  end

  it "includes history as a separate analytics baseline" do
    history = Routing::History.load(File.join(SPEC_ROOT, "data/operations_history.csv"))
    report_with_history = described_class.call(
      decisions: [decision],
      operations: [build_operation],
      providers: pool,
      policy: build_policy,
      history: history
    )

    expect(report_with_history.dig("history_baseline", "vipay", "conversion")).to be_between(0, 1)
  end

  it "includes live provider_metrics from runtime windows" do
    state = Routing::RuntimeState.new(pool)
    state.record_metric!(operation: build_operation, provider_name: "vipay", status: "approved", latency_sec: 12)
    metrics_report = described_class.call(
      decisions: [decision],
      operations: [build_operation],
      providers: pool,
      policy: build_policy,
      runtime_state: state
    )

    expect(metrics_report.dig("provider_metrics", "vipay")).to include(
      "conversion_estimate", "initial_conversion", "initial_timeout_rate",
      "initial_answer_success", "final_approved", "p90_initial_latency_sec"
    )
  end

  it "includes a sequential Brier comparison for observed history" do
    history = Routing::History.load(File.join(SPEC_ROOT, "data/operations_history.csv"))
    report_with_history = described_class.call(
      decisions: [decision], operations: [build_operation], providers: pool,
      policy: build_policy, history: history
    )

    expect(report_with_history.dig("conversion_backtest", "vipay")).to include(
      "sample_size" => be_positive,
      "model_brier" => be_between(0, 1),
      "published_prior_brier" => be_between(0, 1)
    )
  end

  it "uses a resolved timeout status for final traffic share", :aggregate_failures do
    operation = build_operation
    state = Routing::RuntimeState.new(pool)
    reservation = state.try_reserve!(vipay, operation, expected_revision: state.snapshot.revision).reservation
    state.mark_dispatching!(reservation, at: operation.created_at)
    state.mark_timeout!(reservation)
    state.resolve_timeout!(operation_id: operation.id, provider_name: vipay.name, result: "cancelled")
    resolved_report = described_class.call(
      decisions: [expired_decision(operation, vipay)],
      operations: [operation],
      providers: pool,
      policy: build_policy,
      runtime_state: state
    )

    expect(resolved_report.dig("distribution", "vipay", "count")).to eq(0)
    expect(resolved_report.dig("outcomes", "vipay", "rejected")).to eq(1)
    expect(resolved_report.fetch("rejected_operations")).to eq(1)
  end

  def expired_decision(operation, provider)
    Routing::Decision.new(
      operation_id: operation.id,
      selected_provider: provider.name,
      attempts: [],
      simulated_result: "expired",
      latency_sec: 30
    )
  end
end
