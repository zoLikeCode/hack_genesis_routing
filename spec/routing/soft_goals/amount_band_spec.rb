# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::AmountBand do
  it "prefers the provider whose max is closer to the amount", :aggregate_failures do
    payflow = build_provider(limit_amount_min: 500, limit_amount_max: 50_000)
    vipay = build_provider(limit_amount_min: 1_000, limit_amount_max: 100_000)
    operation = build_operation(amount: 48_000)

    expect(described_class.call(payflow, operation, empty_snapshot).score)
      .to be > described_class.call(vipay, operation, empty_snapshot).score
  end

  it "is neutral when the provider has no maximum" do
    provider = build_provider(limit_amount_min: nil, limit_amount_max: nil)

    expect(described_class.call(provider, build_operation, empty_snapshot).score).to eq(0.0)
  end
end
