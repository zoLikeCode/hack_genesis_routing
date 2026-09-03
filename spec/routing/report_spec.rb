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
      "period", "total_operations", "distribution", "skip_reasons",
      "projected_daily_utilization", "recommendations"
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
end
