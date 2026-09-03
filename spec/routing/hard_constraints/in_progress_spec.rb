# frozen_string_literal: true

RSpec.describe Routing::HardConstraints::InProgress do
  let(:operation) { build_operation(amount: 50_000) }

  it "passes when count and amount stay within limits" do
    provider = build_provider(in_progress_count: 1, in_progress_count_limit: 2, in_progress_amount: 10_000)
    expect(described_class.call(provider, operation)).to be_ok
  end

  it "skips when the next request would exceed the count limit" do
    provider = build_provider(in_progress_count: 2, in_progress_count_limit: 2)
    expect(described_class.call(provider, operation)).to be_skipped.and have_attributes(
      reason: "in_progress_count_exceeded"
    )
  end

  it "skips when the next request would exceed the amount limit" do
    provider = build_provider(in_progress_amount: 980_000, in_progress_amount_limit: 1_000_000)
    expect(described_class.call(provider, operation)).to be_skipped.and have_attributes(
      reason: "in_progress_amount_exceeded"
    )
  end

  it "treats nil in-progress limits as unlimited" do
    provider = unlimited_load_provider
    expect(described_class.call(provider, operation)).to be_ok
  end

  def unlimited_load_provider
    build_provider(in_progress_count_limit: nil, in_progress_amount_limit: nil,
                   in_progress_count: 99, in_progress_amount: 9_000_000)
  end
end
