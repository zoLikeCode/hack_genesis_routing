# frozen_string_literal: true

RSpec.describe Routing::Metrics::Catalog do
  let(:provider) { build_provider }
  let(:operation) { build_operation }

  it "uses the published conversion as the empty-window prior" do
    vector = described_class.call(observations: [], provider: provider, operation: operation)

    expect(vector).to have_attributes(
      score: 0.87, prior: 0.87, scope: "prior", source: "published_prior", sample_size: 0
    )
  end

  it "uses the configured fallback prior when conversion_24h is absent" do
    vector = described_class.call(
      observations: [], provider: build_provider(conversion_24h: nil), operation: operation
    )

    expect(vector.score).to eq(0.5)
  end

  it "estimates initial approved probability and reports initial and final outcomes", :aggregate_failures do
    observations = [
      build_observation(operation_id: "a", status: "approved", latency_sec: 20),
      build_observation(operation_id: "b", status: "rejected", latency_sec: 10),
      build_observation(operation_id: "c", initial_status: "expired", status: "approved", latency_sec: 500)
    ]
    vector = described_class.call(observations: observations, provider: provider, operation: operation)

    expect(vector.score).to be_within(0.0001).of((1 + (10 * 0.87)) / 13)
    expect(vector).to have_attributes(
      sample_size: 3, initial_approved_count: 1, initial_rejected_count: 1,
      initial_timeout_count: 1, final_approved_count: 2, final_rejected_count: 1,
      unresolved_count: 0, latency_sample_size: 2
    )
    expect(vector.p90_initial_latency_sec).to be_within(0.0001).of(19.0)
  end

  it "does not change conversion after a late timeout approval" do
    pending = build_observation(operation_id: "late", initial_status: "expired", status: "expired")
    approved = pending.with(status: "approved")

    pending_score = described_class.call(observations: [pending], provider: provider, operation: operation).score
    approved_score = described_class.call(observations: [approved], provider: provider, operation: operation).score

    expect(approved_score).to eq(pending_score)
  end

  it "filters time and causality before taking the bounded tail", :aggregate_failures do
    config = Routing::Metrics::Config.parse(
      "window" => { "max_observations" => 2, "lookback_hours" => 24 }
    )
    past = [
      build_observation(operation_id: "past_1", created_at: operation.created_at - 120, status: "rejected"),
      build_observation(operation_id: "past_2", created_at: operation.created_at - 60, status: "approved"),
      build_observation(operation_id: "past_3", created_at: operation.created_at - 30, status: "approved")
    ]
    future_rows = Array.new(60) do |index|
      build_observation(operation_id: "future_#{index}", created_at: operation.created_at + index + 1)
    end
    vector = described_class.call(
      observations: past + future_rows, provider: provider, operation: operation, config: config
    )

    expect(vector.sample_size).to eq(2)
    expect(vector.initial_approved_count).to eq(2)
  end

  it "uses a segment prior calculated from the rest of provider history", :aggregate_failures do
    segment = Array.new(10) do |index|
      build_observation(operation_id: "seg_#{index}", bank: "sberbank", amount: 15_000, status: "approved")
    end
    rest = Array.new(10) do |index|
      build_observation(operation_id: "rest_#{index}", bank: "tinkoff", amount: 80_000, status: "rejected")
    end
    vector = described_class.call(observations: segment + rest, provider: provider, operation: operation)
    rest_estimate = (10 * 0.87) / 20
    expected = (10 + (10 * rest_estimate)) / 20

    expect(vector).to have_attributes(scope: "bank_amount", sample_size: 10)
    expect(vector.score).to be_within(0.0001).of(expected)
  end

  it "excludes the current operation id at the same timestamp" do
    row = build_observation(operation_id: operation.id, created_at: operation.created_at)
    vector = described_class.call(observations: [row], provider: provider, operation: operation)

    expect(vector.sample_size).to eq(0)
  end
end
