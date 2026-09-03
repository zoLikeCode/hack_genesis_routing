# frozen_string_literal: true

RSpec.describe Routing::HardConstraints::AmountRange do
  let(:provider) { build_provider }

  it "passes an amount inside the range" do
    expect(described_class.call(provider, build_operation(amount: 15_000))).to be_ok
  end

  it "skips below the minimum" do
    result = described_class.call(provider, build_operation(amount: 800))
    expect(result).to be_skipped.and have_attributes(
      reason: "amount_below_minimum", details: "800 < limit_amount_min 1000"
    )
  end

  it "skips above the maximum" do
    result = described_class.call(provider, build_operation(amount: 150_000))
    expect(result).to be_skipped.and have_attributes(
      reason: "amount_exceeds_limit", details: "150000 > limit_amount_max 100000"
    )
  end

  it "treats nil min/max as unlimited" do
    open_range = build_provider(limit_amount_min: nil, limit_amount_max: nil)
    amounts = [1, 1_000_000].map { |amount| described_class.call(open_range, build_operation(amount: amount)) }
    expect(amounts).to all(be_ok)
  end
end
