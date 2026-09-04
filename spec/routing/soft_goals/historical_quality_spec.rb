# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::HistoricalQuality do
  let(:provider) do
    Routing::ProviderPool.load(File.join(SPEC_ROOT, "data/providers.json")).fetch("vipay")
  end
  let(:history) { Routing::History.load(File.join(SPEC_ROOT, "data/operations_history.csv")) }

  it "scores the operation from historical provider context", :aggregate_failures do
    snapshot = empty_snapshot(history: history)
    contribution = described_class.call(provider, build_operation(bank: "sberbank"), snapshot)

    expect(contribution).to have_attributes(name: "historical_quality", reason: "historical_quality")
    expect(contribution.score).to be_between(-1, 1)
    expect(contribution.details).to include("scope=bank", "n=8", "p90_latency_sec=")
  end

  it "is neutral when history was not loaded" do
    contribution = described_class.call(provider, build_operation, empty_snapshot)

    expect(contribution).to have_attributes(score: 0.0, reason: "soft_goal_neutral")
  end
end
