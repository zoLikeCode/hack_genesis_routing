# frozen_string_literal: true

RSpec.describe Routing::Metrics::Catalog do
  let(:provider) { build_provider }
  let(:operation) { build_operation }

  it "uses a neutral approval prior when the window is empty", :aggregate_failures do
    vector = described_class.call(observations: [], provider: provider, operation: operation)

    expect(vector).to have_attributes(scope: "live_prior", sample_size: 0, approval_rate: 0.5, acceptance: 0.5)
    expect(vector.availability).to be_within(0.001).of(0.90)
    expect(vector.health).to be_within(0.0001).of(0.925)
  end

  it "does not take the empty-window prior from conversion_24h" do
    hot = build_provider(conversion_24h: 0.99)
    vector = described_class.call(observations: [], provider: hot, operation: operation)

    expect(vector.approval_rate).to eq(0.5)
  end

  it "pins the default weighted_sum formulas", :aggregate_failures do
    observations = [
      build_observation(operation_id: "a", status: "approved", latency_sec: 20),
      build_observation(operation_id: "b", status: "rejected", latency_sec: 10),
      build_observation(operation_id: "c", status: "expired", latency_sec: 500)
    ]
    vector = described_class.call(observations: observations, provider: provider, operation: operation)

    expect(vector.sample_size).to eq(3)
    expect(vector.approval_rate).to be_within(0.0001).of(6.0 / 13)
    expect(vector.timeout_rate).to be_within(0.0001).of(0.1875)
    expect(vector.availability).to be_within(0.0001).of(0.8125)
    expect(vector.acceptance).to be_within(0.0001).of(0.5)
    expect(vector.p90_latency_sec).to be_within(0.0001).of(19.0)
    expect(vector.latency).to be_within(0.0001).of(581.0 / 600)
    expect(vector.health).to be_within(0.0001).of(0.765625)
    expect(vector.score).to be_within(0.0001).of((2 * expected_raw_quality) - 1)
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

  it "does not let conversion_24h inflate health when every recent attempt timed out", :aggregate_failures do
    observations = Array.new(10) do |index|
      build_observation(operation_id: "exp_#{index}", status: "expired", latency_sec: 500)
    end
    vector = described_class.call(observations: observations, provider: provider, operation: operation)

    expect(vector.acceptance).to be_within(0.0001).of(0.5)
    expect(vector.availability).to be_within(0.0001).of(0.3)
    expect(vector.health).to be_within(0.0001).of(0.475)
  end

  it "includes a previous operation with the same created_at" do
    peer = build_observation(operation_id: "op_peer", created_at: operation.created_at, status: "approved")
    vector = described_class.call(observations: [peer], provider: provider, operation: operation)

    expect(vector.sample_size).to eq(1)
  end

  it "ignores the current operation id even when the timestamp matches" do
    self_row = build_observation(operation_id: operation.id, created_at: operation.created_at, status: "approved")
    vector = described_class.call(observations: [self_row], provider: provider, operation: operation)

    expect(vector).to have_attributes(scope: "live_prior", sample_size: 0)
  end

  it "drops incompatible rows from summarize" do
    rows = [build_observation(operation_id: "blocked", bank: "alfa", status: "approved")]
    vector = described_class.summarize(observations: rows, provider: provider)

    expect(vector).to have_attributes(scope: "live_prior", sample_size: 0)
  end

  def expected_raw_quality
    (0.40 * (6.0 / 13)) + (0.25 * 0.8125) + (0.15 * 0.5) + (0.20 * (581.0 / 600))
  end
end
