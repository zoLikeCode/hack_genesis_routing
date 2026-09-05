# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::LoadBalance do
  it "uses capacity after the candidate reservation" do
    free = build_provider(in_progress_count: 1, in_progress_count_limit: 10)
    busy = build_provider(in_progress_count: 8, in_progress_count_limit: 10)

    free_score = described_class.call(free, build_operation, empty_snapshot).score
    busy_score = described_class.call(busy, build_operation, empty_snapshot).score

    expect(free_score).to be > busy_score
  end

  it "includes the pending request in RPM utilization" do
    at = Time.iso8601("2026-07-30T09:05:00+03:00")
    provider = build_provider(requests_per_minute_limit: 10, in_progress_count_limit: nil,
                              in_progress_amount_limit: nil, daily_amount_limit: nil)
    8.times { provider.record_request!(at) }

    expect(described_class.call(provider, build_operation(created_at: at), empty_snapshot).score)
      .to be_within(1e-10).of(0.1)
  end

  it "returns one when no capacity limits exist" do
    provider = build_provider(in_progress_count_limit: nil, in_progress_amount_limit: nil,
                              requests_per_minute_limit: nil, daily_amount_limit: nil)

    expect(described_class.call(provider, build_operation, empty_snapshot).score).to eq(1.0)
  end
end
