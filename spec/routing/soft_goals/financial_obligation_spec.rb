# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::FinancialObligation do
  let(:operation) { build_operation }

  it "boosts a provider below daily_turnover_min" do
    provider = build_provider(daily_approved_amount: 1_000_000, daily_turnover_min: 2_000_000,
                              daily_turnover_max: nil)
    expect(described_class.call(provider, operation, empty_snapshot))
      .to have_attributes(score: 0.5, reason: "turnover_below_minimum")
  end

  it "penalizes a projected amount over daily_turnover_max" do
    provider = build_provider(daily_approved_amount: 4_400_000, daily_turnover_min: nil,
                              daily_turnover_max: 4_500_000)
    result = described_class.call(provider, build_operation(amount: 150_000), empty_snapshot)
    expect(result.score).to eq(-1.0)
  end

  it "labels an over-max projection as turnover_above_soft_max" do
    provider = build_provider(daily_approved_amount: 4_400_000, daily_turnover_min: nil,
                              daily_turnover_max: 4_500_000)
    result = described_class.call(provider, build_operation(amount: 150_000), empty_snapshot)
    expect(result.reason).to eq("turnover_above_soft_max")
  end

  it "does not penalize turnover well below daily_turnover_max" do
    provider = build_provider(daily_approved_amount: 1_000_000, daily_turnover_min: nil,
                              daily_turnover_max: 4_500_000)
    expect(described_class.call(provider, operation, empty_snapshot))
      .to have_attributes(score: 0.0, reason: "soft_goal_neutral")
  end

  it "does not skip a provider that misses a financial target" do
    provider = build_provider(daily_approved_amount: 4_400_000, daily_turnover_max: 4_500_000)
    expect(described_class.call(provider, operation, empty_snapshot)).to be_a(Routing::SoftGoals::Contribution)
  end

  it "returns a neutral score when both floors and ceilings are nil" do
    provider = build_provider(daily_turnover_min: nil, daily_turnover_max: nil)
    expect(described_class.call(provider, operation, empty_snapshot))
      .to have_attributes(score: 0.0, reason: "soft_goal_neutral")
  end
end
