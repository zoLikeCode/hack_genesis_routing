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

  it "evaluates each provider with its own profile", :aggregate_failures do
    provider_policy = Routing::Policy.new(
      "strategies" => {},
      "profiles" => {
        "conversion_only" => { "strategies" => { "conversion" => { "weight" => 1.0 } } },
        "cascade_only" => { "strategies" => { "cascade_priority" => { "weight" => 1.0 } } }
      },
      "provider_profiles" => { "vipay" => "cascade_only", "payflow" => "conversion_only" }
    )
    result = described_class.call(
      eligible: [vipay, payflow],
      operation: build_operation,
      snapshot: empty_snapshot,
      policy: provider_policy
    )

    expect(result.scores.fetch("vipay").contributions.map(&:name)).to eq(["cascade_priority"])
    expect(result.scores.fetch("payflow").contributions.map(&:name)).to eq(["conversion"])
  end

  it "keeps every eligible provider in the ranking" do
    expect(ranking.ordered).to contain_exactly(vipay, payflow)
  end

  it "applies health after the weighted soft total", :aggregate_failures do
    result = health_ranking

    expect(result.preferred.name).to eq("payflow")
    expect(result.scores.fetch("payflow").health).to be > result.scores.fetch("vipay").health
    expect(result.scores.fetch("vipay").total).to eq(
      result.scores.fetch("vipay").base_total * result.scores.fetch("vipay").health
    )
  end

  it "records a metric disagreement when quality signals prefer different providers" do
    expect(metric_conflict_ranking.conflicts.map(&:kind)).to include("metric_disagreement")
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

  def health_ranking
    healthy = build_provider(payment_system: "payflow", conversion_24h: 0.80, traffic_percentage: 40, priority: 2)
    unhealthy = build_provider(conversion_24h: 0.80)
    pool = Routing::ProviderPool.new([unhealthy, healthy])
    store = Routing::Metrics::Store.seed(history: nil, providers: pool, config: nil)
    5.times do |index|
      store.record(build_observation(operation_id: "exp_#{index}", provider_name: "vipay", status: "expired"))
      store.record(build_observation(operation_id: "ok_#{index}", provider_name: "payflow", status: "approved"))
    end
    described_class.call(
      eligible: [unhealthy, healthy],
      operation: build_operation,
      snapshot: empty_snapshot(metrics: store.snapshot),
      policy: build_policy("conversion" => { "enabled" => true, "weight" => 1.0 })
    )
  end

  def metric_conflict_ranking
    refused = build_provider(conversion_24h: 0.50)
    timed_out = build_provider(payment_system: "payflow", conversion_24h: 0.50, traffic_percentage: 40, priority: 2)
    pool = Routing::ProviderPool.new([refused, timed_out])
    store = Routing::Metrics::Store.seed(history: nil, providers: pool, config: nil)
    5.times do |index|
      store.record(build_observation(operation_id: "rej_#{index}", provider_name: "vipay", status: "rejected"))
      store.record(build_observation(operation_id: "exp_#{index}", provider_name: "payflow", status: "expired"))
    end
    described_class.call(
      eligible: [refused, timed_out],
      operation: build_operation,
      snapshot: empty_snapshot(metrics: store.snapshot),
      policy: build_policy("conversion" => { "enabled" => true, "weight" => 1.0 })
    )
  end
end
