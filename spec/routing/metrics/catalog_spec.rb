# frozen_string_literal: true

RSpec.describe Routing::Metrics::Catalog do
  let(:provider) { build_provider }
  let(:operation) { build_operation }

  it "uses the live conversion as a prior when the window is empty", :aggregate_failures do
    vector = described_class.call(observations: [], provider: provider, operation: operation)

    expect(vector).to have_attributes(scope: "live_prior", sample_size: 0, approval_rate: 0.87)
    expect(vector.availability).to be_within(0.001).of(0.90)
    expect(vector.health).to be_between(0.25, 1.0)
  end

  it "scores approval, availability, and acceptance from observations", :aggregate_failures do
    observations = [
      build_observation(operation_id: "a", status: "approved", latency_sec: 20),
      build_observation(operation_id: "b", status: "rejected", latency_sec: 10),
      build_observation(operation_id: "c", status: "expired", latency_sec: 500)
    ]
    vector = described_class.call(observations: observations, provider: provider, operation: operation)

    expect(vector.sample_size).to eq(3)
    expect(vector.approval_rate).to be_between(0, 1)
    expect(vector.availability).to be < 1.0
    expect(vector.acceptance).to be_between(0, 1)
    expect(vector.score).to be_between(-1, 1)
  end

  it "computes health from the recent slice" do
    observations = [
      build_observation(operation_id: "old", status: "approved",
                        created_at: Time.iso8601("2026-07-30T07:00:00+03:00")),
      build_observation(operation_id: "new", status: "expired",
                        created_at: Time.iso8601("2026-07-30T08:00:00+03:00"))
    ]
    config = Routing::Metrics::Config.parse(
      "window" => { "recent_observations" => 1 },
      "multipliers" => { "health" => { "availability_weight" => 1.0, "acceptance_weight" => 0.0 } }
    )
    vector = described_class.call(
      observations: observations, provider: provider, operation: operation, config: config
    )

    expect(vector.health).to be < 0.9
  end
end
