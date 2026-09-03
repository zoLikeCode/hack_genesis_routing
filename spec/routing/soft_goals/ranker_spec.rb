# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::Ranker do
  subject(:ranking) do
    described_class.call(eligible: [vipay, payflow], operation: build_operation,
                         snapshot: empty_snapshot, policy: policy)
  end

  let(:policy) { build_policy }
  let(:vipay) { build_provider }
  let(:payflow) { payflow_provider }

  it "orders eligible providers by weighted total" do
    expect(ranking.ordered.map(&:name)).to eq(%w[vipay payflow])
  end

  it "exposes the highest-scoring provider as preferred" do
    expect(ranking.preferred).to eq(vipay)
  end

  it "gives vipay a higher total than payflow on an empty session" do
    expect(ranking.scores.fetch("vipay").total).to be > ranking.scores.fetch("payflow").total
  end

  it "breaks ties by lower priority then name" do
    result = described_class.call(eligible: tie_providers, operation: build_operation,
                                  snapshot: empty_snapshot, policy: disabled_policy)
    expect(result.ordered.map(&:name)).to eq(%w[vipay payflow])
  end

  it "uses only_eligible_provider when a single candidate remains" do
    result = described_class.call(eligible: [vipay], operation: build_operation,
                                  snapshot: empty_snapshot, policy: policy)
    expect(result.scores.fetch("vipay").reason).to eq("only_eligible_provider")
  end

  it "records a conflict when count-share and financial obligation disagree" do
    expect(conflict_ranking.conflicts.map(&:kind)).to include("goal_disagreement")
  end

  it "prefers the higher weighted total when goals disagree" do
    expect(conflict_ranking.preferred.name).to eq("payflow")
  end

  it "ranks remaining providers when a count target is unreachable" do
    expect(unmet_ranking.preferred).to eq(payflow)
  end

  it "notes an unmet count-share target" do
    expect(unmet_ranking.notes).to include("unmet_count_share: vipay")
  end

  it "keeps every eligible provider in the ranking" do
    expect(ranking.ordered).to contain_exactly(vipay, payflow)
  end

  def payflow_provider
    build_provider(payment_system: "payflow", traffic_percentage: 35, priority: 2,
                   conversion_24h: 0.91, volume_share_pct: 20,
                   daily_turnover_min: 2_000_000, daily_turnover_max: nil)
  end

  def disabled_policy
    build_policy(default_strategy_weights.transform_values { |entry| entry.merge("enabled" => false) })
  end

  def tie_providers
    opts = { conversion_24h: nil, volume_share_pct: nil, daily_turnover_min: nil, daily_turnover_max: nil }
    [
      build_provider(**opts, payment_system: "payflow", priority: 2),
      build_provider(**opts, payment_system: "vipay", priority: 1)
    ]
  end

  def conflict_ranking
    described_class.call(
      eligible: conflict_providers,
      operation: build_operation(amount: 150_000),
      snapshot: empty_snapshot,
      policy: conflict_policy
    )
  end

  def conflict_policy
    build_policy(
      "count_share" => { "enabled" => true, "weight" => 0.30 },
      "volume_share" => { "enabled" => false, "weight" => 0.20 },
      "conversion" => { "enabled" => false, "weight" => 0.20 },
      "cascade_priority" => { "enabled" => false, "weight" => 0.10 },
      "financial_obligation" => { "enabled" => true, "weight" => 0.05 }
    )
  end

  def conflict_providers
    [
      build_provider(daily_approved_amount: 4_400_000, daily_turnover_min: nil,
                     daily_turnover_max: 4_500_000, conversion_24h: nil, volume_share_pct: nil),
      build_provider(payment_system: "payflow", traffic_percentage: 35, priority: 2,
                     daily_approved_amount: 0, daily_turnover_min: 2_000_000,
                     daily_turnover_max: nil, conversion_24h: nil, volume_share_pct: nil)
    ]
  end

  def unmet_ranking
    described_class.call(
      eligible: [payflow],
      operation: build_operation,
      snapshot: empty_snapshot(count_targets: { "vipay" => 40, "payflow" => 35 }),
      policy: policy
    )
  end
end
