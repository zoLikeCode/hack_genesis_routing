# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::CascadePriority do
  it "prefers a lower priority number" do
    first = described_class.call(build_provider(priority: 1), build_operation, empty_snapshot)
    second = described_class.call(build_provider(priority: 2), build_operation, empty_snapshot)
    expect(first.score).to be > second.score
  end

  it "records cascade_priority as the reason" do
    result = described_class.call(build_provider(priority: 1), build_operation, empty_snapshot)
    expect(result.reason).to eq("cascade_priority")
  end

  it "returns a neutral score when priority is nil" do
    result = described_class.call(build_provider(priority: nil), build_operation, empty_snapshot)
    expect(result).to have_attributes(score: 0.0, reason: "soft_goal_neutral")
  end
end
