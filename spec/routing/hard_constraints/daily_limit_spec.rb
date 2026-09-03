# frozen_string_literal: true

RSpec.describe Routing::HardConstraints::DailyLimit do
  let(:operation) { build_operation(amount: 150) }

  it "passes when projected turnover is within the daily cap" do
    provider = build_provider(daily_approved_amount: 900, daily_amount_limit: 1_100)
    expect(described_class.call(provider, operation)).to be_ok
  end

  it "skips when projected turnover exceeds the daily cap" do
    provider = build_provider(daily_approved_amount: 900, daily_amount_limit: 1_000)
    result = described_class.call(provider, operation)
    expect(result).to be_skipped.and have_attributes(
      reason: "daily_limit_exceeded", details: "1050 > daily_amount_limit 1000"
    )
  end

  it "treats a nil daily limit as unlimited" do
    provider = build_provider(daily_amount_limit: nil, daily_approved_amount: 0)
    expect(described_class.call(provider, build_operation(amount: 10_000_000))).to be_ok
  end
end
