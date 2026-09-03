# frozen_string_literal: true

RSpec.describe Routing::Router do
  subject(:selection) do
    described_class.call(
      operation: operation,
      providers: providers,
      snapshot: snapshot,
      policy: policy,
      attempted: attempted
    )
  end

  let(:operation) { build_operation }
  let(:providers) { [vipay_provider, payflow_provider, fallback_provider] }
  let(:snapshot) { Routing::SoftGoals::Snapshot.from_providers(providers) }
  let(:policy) do
    build_policy("conversion" => { "enabled" => true, "weight" => 1.0 })
  end
  let(:attempted) { [] }

  it "ranks only eligible external providers" do
    expect(selection.ranking.ordered.map(&:name)).to eq(%w[payflow vipay])
  end

  it "does not let fallback compete in soft goals" do
    expect(selection.ranking.ordered.map(&:name)).not_to include("spacepayments")
  end

  it "selects the highest-ranked external provider" do
    expect(selection.provider.name).to eq("payflow")
    expect(selection.fallback?).to be(false)
  end

  context "when an external provider fails a hard constraint" do
    let(:providers) { [build_provider(status: "disabled", conversion_24h: 1.0), payflow_provider, fallback_provider] }

    it "excludes it before soft-goal ranking" do
      expect(selection.provider.name).to eq("payflow")
      expect(selection.evaluation.skipped.map(&:provider)).to include("vipay")
    end
  end

  context "when the preferred provider has already been attempted" do
    let(:attempted) { ["payflow"] }

    it "reruns ranking for the remaining external providers" do
      expect(selection.provider.name).to eq("vipay")
      expect(selection.ranking.ordered.map(&:name)).to eq(["vipay"])
    end
  end

  context "when every external provider has already been attempted" do
    let(:attempted) { %w[vipay payflow] }

    it "selects the hard-constraint-eligible fallback" do
      expect(selection.provider.name).to eq("spacepayments")
      expect(selection.fallback?).to be(true)
      expect(selection.ranking.ordered).to be_empty
    end
  end

  context "when fallback also fails a hard constraint" do
    let(:attempted) { %w[vipay payflow] }
    let(:providers) { [vipay_provider, payflow_provider, fallback_provider(status: "disabled")] }

    it "returns an unroutable selection instead of bypassing hard constraints" do
      expect(selection.provider).to be_nil
      expect(selection.routable?).to be(false)
      expect(selection.fallback?).to be(false)
    end
  end

  it "rejects an unknown attempted provider" do
    expect do
      described_class.call(
        operation: operation,
        providers: providers,
        snapshot: snapshot,
        policy: policy,
        attempted: ["unknown"]
      )
    end.to raise_error(Routing::InvariantError, "attempted contains unknown providers: unknown")
  end

  def vipay_provider
    build_provider(conversion_24h: 0.87)
  end

  def payflow_provider
    build_provider(
      payment_system: "payflow",
      traffic_percentage: 35,
      priority: 2,
      conversion_24h: 0.91
    )
  end

  def fallback_provider(**overrides)
    build_provider(
      payment_system: "spacepayments",
      traffic_percentage: 0,
      priority: 99,
      conversion_24h: 0.99,
      limit_amount_min: nil,
      limit_amount_max: nil,
      daily_amount_limit: nil,
      in_progress_count_limit: nil,
      in_progress_amount_limit: nil,
      banks: [],
      **overrides
    )
  end
end
