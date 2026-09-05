# frozen_string_literal: true

RSpec.describe Routing::Metrics::Window do
  subject(:window) { described_class.new(max_observations: 2) }

  it "evicts the oldest attempt regardless of outcome" do
    window.record(build_observation(operation_id: "a", status: "expired"))
    window.record(build_observation(operation_id: "b", status: "approved"))
    window.record(build_observation(operation_id: "c", status: "rejected"))

    expect(window.observations.map(&:operation_id)).to eq(%w[b c])
  end

  it "rewrites only final status and preserves initial evidence", :aggregate_failures do
    window.record(build_observation(operation_id: "a", initial_status: "expired", status: "expired", latency_sec: 40))
    rewritten = window.rewrite_status(operation_id: "a", status: "approved")

    expect(rewritten).to have_attributes(initial_status: "expired", status: "approved", latency_sec: 40)
  end

  it "does not restore an evicted attempt", :aggregate_failures do
    window.record(build_observation(operation_id: "old", status: "expired"))
    window.record(build_observation(operation_id: "new"))
    window.record(build_observation(operation_id: "newest"))

    expect(window.rewrite_status(operation_id: "old", status: "approved")).to be_nil
    expect(window.observations.map(&:operation_id)).to eq(%w[new newest])
  end
end
