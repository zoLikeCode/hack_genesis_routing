# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::LoadBalance do
  it "prefers a provider with more free in-progress capacity" do
    free = build_provider(in_progress_count: 1, in_progress_count_limit: 10)
    busy = build_provider(in_progress_count: 8, in_progress_count_limit: 10)

    free_score = described_class.call(free, build_operation, empty_snapshot).score
    busy_score = described_class.call(busy, build_operation, empty_snapshot).score

    expect(free_score).to be > busy_score
  end

  it "treats RPM pressure as load" do
    at = Time.iso8601("2026-07-30T09:05:00+03:00")
    free = build_provider(requests_per_minute_limit: 10, in_progress_count_limit: nil, in_progress_amount_limit: nil)
    busy = build_provider(requests_per_minute_limit: 10, in_progress_count_limit: nil, in_progress_amount_limit: nil)
    8.times { busy.record_request!(at) }
    operation = build_operation(created_at: at.iso8601)

    expect(described_class.call(free, operation, empty_snapshot).score)
      .to be > described_class.call(busy, operation, empty_snapshot).score
  end

  it "is neutral when load limits are unlimited" do
    provider = build_provider(
      in_progress_count_limit: nil,
      in_progress_amount_limit: nil,
      requests_per_minute_limit: nil
    )

    expect(described_class.call(provider, build_operation, empty_snapshot).score).to eq(0.0)
  end
end
