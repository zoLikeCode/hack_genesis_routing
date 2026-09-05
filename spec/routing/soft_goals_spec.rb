# frozen_string_literal: true

RSpec.describe Routing::SoftGoals do
  it "declares metrics on every strategy" do
    undeclared = described_class::GOALS.reject { |goal| goal::METRICS.any? }
    expect(undeclared).to eq([])
  end

  it "exposes those lists through metric_map" do
    expect(described_class.metric_map).to eq(
      described_class::GOALS.to_h { |goal| [goal::KEY, goal::METRICS] }
    )
  end
end
