# frozen_string_literal: true

RSpec.describe Routing::Metrics::Window do
  subject(:window) { described_class.new(max_observations: 2) }

  it "keeps only the newest observations" do
    window.record(build_observation(operation_id: "a", status: "approved"))
    window.record(build_observation(operation_id: "b", status: "rejected"))
    window.record(build_observation(operation_id: "c", status: "expired"))

    expect(window.observations.map(&:operation_id)).to eq(%w[b c])
  end

  it "rewrites status for an existing operation" do
    window.record(build_observation(operation_id: "a", status: "expired"))
    window.rewrite_status(operation_id: "a", status: "approved")

    expect(window.observations.first.status).to eq("approved")
  end

  it "returns the most recent slice" do
    window.record(build_observation(operation_id: "a"))
    window.record(build_observation(operation_id: "b"))

    expect(window.recent(1).map(&:operation_id)).to eq(%w[b])
  end
end
