# frozen_string_literal: true

RSpec.describe Routing::Metrics::Store do
  let(:provider) { build_provider }
  let(:pool) { Routing::ProviderPool.new([provider]) }

  it "keeps source history so Catalog can filter time before taking its bounded tail" do
    rows = Array.new(60) { |index| build_observation(operation_id: "op_#{index}") }
    history = Routing::History.new({}, observations: rows)
    store = described_class.seed(history: history, providers: pool, config: nil)

    expect(store.observations_for("vipay").size).to eq(60)
  end

  it "records one live attempt per provider and operation" do
    store = described_class.seed(history: nil, providers: pool, config: nil)
    store.record(build_observation(operation_id: "live", status: "expired"))
    store.record(build_observation(operation_id: "live", status: "approved"))

    expect(store.observations_for("vipay").map(&:status)).to eq(%w[approved])
  end

  it "updates a retained timeout without restoring a missing one", :aggregate_failures do
    store = described_class.seed(history: nil, providers: pool, config: nil)
    store.record(build_observation(operation_id: "late", initial_status: "expired", status: "expired", latency_sec: 40))
    store.update_status(operation_id: "late", provider_name: "vipay", status: "approved")
    store.update_status(operation_id: "missing", provider_name: "vipay", status: "approved")

    expect(store.observations_for("vipay").first).to have_attributes(
      initial_status: "expired", status: "approved", latency_sec: 40
    )
    expect(store.observations_for("vipay").size).to eq(1)
  end
end
