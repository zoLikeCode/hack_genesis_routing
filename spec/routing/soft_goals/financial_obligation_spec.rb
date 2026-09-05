# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::FinancialObligation do
  it "maps neutral obligation state to one half" do
    provider = build_provider(daily_turnover_min: nil, daily_turnover_max: nil)

    expect(described_class.call(provider, build_operation, empty_snapshot).score).to eq(0.5)
  end

  it "uses projected turnover to reward a remaining minimum deficit", :aggregate_failures do
    provider = build_provider(daily_approved_amount: 1_000_000, daily_turnover_min: 2_000_000,
                              daily_turnover_max: nil)
    result = described_class.call(provider, build_operation(amount: 100_000), empty_snapshot)

    expect(result.score).to be_within(0.0001).of((1 + 0.45) / 2)
    expect(result.reason).to eq("turnover_below_minimum")
  end

  it "penalizes projected turnover past the soft maximum", :aggregate_failures do
    provider = build_provider(daily_approved_amount: 4_400_000, daily_turnover_min: nil,
                              daily_turnover_max: 4_500_000)
    result = described_class.call(provider, build_operation(amount: 150_000), empty_snapshot)

    expect(result.score).to eq(0.0)
    expect(result.reason).to eq("turnover_above_soft_max")
  end
end
