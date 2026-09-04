# frozen_string_literal: true

RSpec.describe Routing::Metrics::Store do
  subject(:store) do
    described_class.seed(history: history, providers: pool, config: nil)
  end

  let(:vipay) { build_provider }
  let(:pool) { Routing::ProviderPool.new([vipay]) }
  let(:history) { Routing::History.new({}, observations: observations) }
  let(:observations) { [] }

  it "seeds a truncated compatible window from history" do
    rows = Array.new(3) do |index|
      build_observation(operation_id: "op_#{index}", created_at: Time.iso8601("2026-07-30T08:0#{index}:00+03:00"))
    end
    local = described_class.seed(
      history: Routing::History.new({}, observations: rows),
      providers: pool,
      config: { "window" => { "max_observations" => 2, "recent_observations" => 1 } }
    )

    expect(local.observations_for("vipay").map(&:operation_id)).to eq(%w[op_1 op_2])
  end

  it "ignores history rows that violate current bank rules" do
    rows = [build_observation(operation_id: "blocked", bank: "alfa")]
    local = described_class.seed(
      history: Routing::History.new({}, observations: rows),
      providers: pool,
      config: nil
    )

    expect(local.observations_for("vipay")).to be_empty
  end

  it "records a live attempt on the provider window" do
    store.record(build_observation(operation_id: "live", status: "rejected"))

    expect(store.observations_for("vipay").map(&:status)).to eq(%w[rejected])
  end
end
