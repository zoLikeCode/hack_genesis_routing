# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::AmountBand do
  it "prefers an amount near the center of the provider range", :aggregate_failures do
    provider = build_provider(limit_amount_min: 0, limit_amount_max: 100_000)
    center = described_class.call(provider, build_operation(amount: 50_000), empty_snapshot)
    edge = described_class.call(provider, build_operation(amount: 100_000), empty_snapshot)

    expect(center.score).to eq(1.0)
    expect(edge.score).to eq(0.0)
  end

  it "is neutral when the provider has no complete range" do
    provider = build_provider(limit_amount_min: nil, limit_amount_max: nil)

    expect(described_class.call(provider, build_operation, empty_snapshot).score).to eq(0.0)
  end
end
