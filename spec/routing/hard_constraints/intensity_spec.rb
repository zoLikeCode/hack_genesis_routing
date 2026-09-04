# frozen_string_literal: true

RSpec.describe Routing::HardConstraints::Intensity do
  let(:at) { Time.iso8601("2026-07-30T09:05:00+03:00") }
  let(:operation) { build_operation(created_at: at.iso8601) }

  it "passes when the request count is under the limit" do
    expect(described_class.call(fill_window(limit: 2, count: 1), operation)).to be_ok
  end

  it "skips when the request count is at the limit" do
    result = described_class.call(fill_window(limit: 2, count: 2), operation)
    expect(result).to be_skipped.and have_attributes(reason: "rate_limit_exceeded")
  end

  it "skips when the request count is over the limit" do
    result = described_class.call(fill_window(limit: 2, count: 3), operation)
    expect(result).to be_skipped.and have_attributes(reason: "rate_limit_exceeded")
  end

  it "ignores a nil rate limit" do
    expect(described_class.call(fill_window(limit: nil, count: 10), operation)).to be_ok
  end

  it "raises InvalidInputError when created_at is missing and a rate limit is set" do
    provider = build_provider(requests_per_minute_limit: 2)
    operation = build_operation(created_at: nil)

    expect { described_class.call(provider, operation) }.to raise_error(
      Routing::InvalidInputError,
      "created_at required for intensity check"
    )
  end

  def fill_window(limit:, count:)
    provider = build_provider(requests_per_minute_limit: limit)
    count.times { |index| provider.record_request!(at - index) }
    provider
  end
end
