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

  it "seeds each provider with its overlay window size", :aggregate_failures do
    payflow = build_provider(payment_system: "payflow")
    stamp = lambda do |name, index|
      build_observation(
        operation_id: "#{name}_#{index}",
        provider_name: name,
        created_at: Time.iso8601("2026-07-30T08:0#{index}:00+03:00")
      )
    end
    rows = 3.times.flat_map { |index| [stamp.call("vipay", index), stamp.call("payflow", index)] }
    local = described_class.seed(
      history: Routing::History.new({}, observations: rows),
      providers: Routing::ProviderPool.new([vipay, payflow]),
      config: { "window" => { "max_observations" => 3, "recent_observations" => 1 } },
      config_for: lambda do |provider|
        size = provider.name == "vipay" ? 2 : 3
        { "window" => { "max_observations" => size, "recent_observations" => 1 } }
      end
    )

    expect(local.observations_for("vipay").map(&:operation_id)).to eq(%w[vipay_1 vipay_2])
    expect(local.observations_for("payflow").map(&:operation_id)).to eq(%w[payflow_0 payflow_1 payflow_2])
  end

  it "reinserts a trimmed timeout when status-check settles" do
    local = described_class.seed(
      history: nil,
      providers: pool,
      config: { "window" => { "max_observations" => 1, "recent_observations" => 1 } }
    )
    expired = build_observation(operation_id: "late", status: "expired", latency_sec: 40)
    local.record(expired)
    local.record(build_observation(operation_id: "newer", status: "expired", latency_sec: 40))
    local.update_status(
      operation_id: "late",
      provider_name: "vipay",
      status: "approved",
      observation: expired
    )

    restored = local.observations_for("vipay").find { |row| row.operation_id == "late" }
    expect(restored).to have_attributes(status: "approved", latency_sec: nil)
  end
end
