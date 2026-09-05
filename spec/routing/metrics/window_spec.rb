# frozen_string_literal: true

RSpec.describe Routing::Metrics::Window do
  subject(:window) { described_class.new(max_observations: 2) }

  it "keeps only the newest observations" do
    window.record(build_observation(operation_id: "a", status: "approved"))
    window.record(build_observation(operation_id: "b", status: "rejected"))
    window.record(build_observation(operation_id: "c", status: "expired"))

    expect(window.observations.map(&:operation_id)).to eq(%w[b c])
  end

  it "drops settled rows before pending timeouts" do
    window.record(build_observation(operation_id: "a", status: "expired"))
    window.record(build_observation(operation_id: "b", status: "approved"))
    window.record(build_observation(operation_id: "c", status: "approved"))

    expect(window.observations.map(&:operation_id)).to eq(%w[a c])
  end

  it "rewrites status and clears timeout latency", :aggregate_failures do
    window.record(build_observation(operation_id: "a", status: "expired", latency_sec: 40))
    rewritten = window.rewrite_status(operation_id: "a", status: "approved")

    expect(rewritten).to have_attributes(status: "approved", latency_sec: nil)
  end

  it "returns false when the operation is no longer in the window" do
    expect(window.rewrite_status(operation_id: "missing", status: "approved")).to be_nil
  end

  it "returns the most recent slice" do
    window.record(build_observation(operation_id: "a"))
    window.record(build_observation(operation_id: "b"))

    expect(window.recent(1).map(&:operation_id)).to eq(%w[b])
  end
end
