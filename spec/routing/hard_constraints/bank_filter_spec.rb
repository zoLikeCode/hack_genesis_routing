# frozen_string_literal: true

RSpec.describe Routing::HardConstraints::BankFilter do
  let(:operation) { build_operation(bank: "alfa") }

  it "passes when the bank is on the allowlist" do
    provider = build_provider(banks: %w[sberbank alfa], exclude_banks: false)
    expect(described_class.call(provider, operation)).to be_ok
  end

  it "skips when the bank is missing from the allowlist" do
    provider = build_provider(banks: %w[sberbank tinkoff], exclude_banks: false)
    expect(described_class.call(provider, operation)).to be_skipped.and have_attributes(reason: "bank_not_in_list")
  end

  it "skips when the bank is on the blocklist" do
    provider = build_provider(banks: %w[alfa], exclude_banks: true)
    expect(described_class.call(provider, operation)).to be_skipped.and have_attributes(reason: "bank_excluded")
  end

  it "accepts every bank when the list is empty" do
    expect(described_class.call(build_provider(banks: []), operation)).to be_ok
  end
end
