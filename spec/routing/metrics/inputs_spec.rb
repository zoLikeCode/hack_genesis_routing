# frozen_string_literal: true

RSpec.describe Routing::Metrics::Inputs do
  it "registers unique keys" do
    expect(described_class.keys.uniq).to eq(described_class.keys)
  end

  it "only uses known sources" do
    expect(described_class::ALL.map(&:source).uniq).to match_array(described_class::SOURCES)
  end

  it "covers every metric a strategy combines" do
    used = Routing::SoftGoals.metric_map.values.flatten
    expect(used - described_class.keys).to eq([])
  end
end
