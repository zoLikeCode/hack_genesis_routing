# frozen_string_literal: true

RSpec.describe Routing::Simulator do
  it "returns the same results for the same seed" do
    first = described_class.new(seed: 42)
    second = described_class.new(seed: 42)
    provider = build_provider
    expect(first.call(provider)).to eq(second.call(provider))
  end

  it "always approves when conversion_24h is 1.0" do
    simulator = described_class.new(seed: 1)
    provider = build_provider(conversion_24h: 1.0)
    results = Array.new(20) { simulator.call(provider).fetch(:result) }
    expect(results).to all(eq("approved"))
  end

  it "never approves when conversion_24h is 0" do
    simulator = described_class.new(seed: 1)
    provider = build_provider(conversion_24h: 0)
    results = Array.new(20) { simulator.call(provider).fetch(:result) }
    expect(results).to all(eq("rejected").or(eq("expired")))
  end

  it "treats missing conversion as always approved" do
    simulator = described_class.new(seed: 7)
    provider = build_provider(conversion_24h: nil)
    expect(simulator.call(provider).fetch(:result)).to eq("approved")
  end

  it "rounds avg_latency_sec" do
    simulator = described_class.new(seed: 1)
    provider = build_provider(conversion_24h: 1.0, avg_latency_sec: 38)
    expect(simulator.call(provider).fetch(:latency_sec)).to eq(38)
  end

  it "returns a stable terminal status for a timed-out payout", :aggregate_failures do
    simulator = described_class.new(seed: 4)
    provider = build_provider(conversion_24h: 0)
    outcome = simulator.call(provider, operation: build_operation, idempotency_key: "op_test:vipay")

    first = simulator.status(provider, operation_id: "op_test", idempotency_key: "op_test:vipay")
    second = simulator.status(provider, operation_id: "op_test", idempotency_key: "op_test:vipay")

    expect(outcome.fetch(:result)).to eq("expired")
    expect(first).to eq(result: "rejected")
    expect(second).to eq(first)
  end
end
