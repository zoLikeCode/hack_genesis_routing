# frozen_string_literal: true

RSpec.describe Routing::Decision do
  subject(:decision) do
    described_class.new(
      operation_id: "op_test",
      selected_provider: "vipay",
      attempts: [selected_attempt],
      simulated_result: "approved",
      latency_sec: 30
    )
  end

  let(:selected_attempt) do
    Routing::HardConstraints::Attempt.new(provider: "vipay", decision: "selected", reason: "only_eligible_provider")
  end

  it "serializes the required decision fields" do
    expect(decision.to_h).to include("operation_id" => "op_test", "selected_provider" => "vipay")
  end

  it "serializes simulated_result and latency" do
    expect(decision.to_h).to include("simulated_result" => "approved", "latency_sec" => 30)
  end

  it "serializes attempts" do
    expect(decision.to_h.fetch("attempts")).to eq([selected_attempt.to_h])
  end

  it "rejects an unknown simulated_result" do
    expect { invalid_decision }.to raise_error(Routing::InvariantError)
  end

  def invalid_decision
    described_class.new(
      operation_id: "op_test", selected_provider: "vipay", attempts: [selected_attempt],
      simulated_result: "maybe", latency_sec: 1
    )
  end
end
