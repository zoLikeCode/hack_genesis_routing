# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::LoadBalance do
  it "prefers a provider with more free in-progress capacity" do
    free = build_provider(in_progress_count: 1, in_progress_count_limit: 10)
    busy = build_provider(in_progress_count: 8, in_progress_count_limit: 10)

    free_score = described_class.call(free, build_operation, empty_snapshot).score
    busy_score = described_class.call(busy, build_operation, empty_snapshot).score

    expect(free_score).to be > busy_score
  end

  it "is neutral when both load limits are unlimited" do
    provider = build_provider(in_progress_count_limit: nil, in_progress_amount_limit: nil)

    expect(described_class.call(provider, build_operation, empty_snapshot).score).to eq(0.0)
  end
end
