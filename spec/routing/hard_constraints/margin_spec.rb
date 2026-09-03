# frozen_string_literal: true

RSpec.describe Routing::HardConstraints::Margin do
  let(:operation) { build_operation }

  it "passes when provider margin is within the merchant margin" do
    expect(described_class.call(build_provider, operation)).to be_ok
  end

  it "skips when provider margin exceeds merchant margin" do
    provider = build_provider(provider_margin_pct: 2.0, merchant_margin_pct: 1.5, allow_negative_agreement: false)
    expect(described_class.call(provider, operation)).to be_skipped.and have_attributes(reason: "negative_margin")
  end

  it "passes a negative margin when an agreement allows it" do
    provider = build_provider(provider_margin_pct: 2.0, merchant_margin_pct: 1.5, allow_negative_agreement: true)
    expect(described_class.call(provider, operation)).to be_ok
  end
end
