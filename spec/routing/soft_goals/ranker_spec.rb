# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::Ranker do
  let(:vipay) { build_provider(traffic_percentage: 60, conversion_24h: 0.8) }
  let(:payflow) do
    build_provider(payment_system: "payflow", traffic_percentage: 40, priority: 2,
                   conversion_24h: 0.9, volume_share_pct: 50)
  end
  let(:snapshot) { Routing::SoftGoals::Snapshot.from_providers([vipay, payflow]) }

  it "uses the normalized weighted sum without an extra multiplier" do
    policy = Routing::Policy.new(
      "strategies" => {
        "conversion" => { "enabled" => true, "weight" => 3 },
        "load_balance" => { "enabled" => true, "weight" => 1 }
      }
    )
    ranking = described_class.call(
      eligible: [vipay, payflow], operation: build_operation, snapshot: snapshot, policy: policy
    )
    score = ranking.scores.fetch("payflow")
    expected = (0.75 * score.contribution("conversion").score) +
               (0.25 * score.contribution("load_balance").score)

    expect(score.total).to be_within(1e-10).of(expected)
  end

  it "prefers a higher conversion estimate under the same profile" do
    policy = build_policy("conversion" => { "enabled" => true, "weight" => 1 })
    ranking = described_class.call(
      eligible: [vipay, payflow], operation: build_operation, snapshot: snapshot, policy: policy
    )

    expect(ranking.preferred).to eq(payflow)
  end

  it "breaks equal totals by priority and then name" do
    equal = build_provider(payment_system: "equal", traffic_percentage: 0, priority: 1, conversion_24h: 0.8)
    policy = build_policy("conversion" => { "enabled" => true, "weight" => 1 })
    ranking = described_class.call(
      eligible: [equal, vipay], operation: build_operation,
      snapshot: Routing::SoftGoals::Snapshot.from_providers([equal, vipay]), policy: policy
    )

    expect(ranking.ordered.map(&:name)).to eq(%w[equal vipay])
  end

  it "marks the only remaining provider" do
    ranking = described_class.call(
      eligible: [vipay], operation: build_operation, snapshot: snapshot,
      policy: build_policy("conversion" => { "enabled" => true, "weight" => 1 })
    )

    expect(ranking.scores.fetch("vipay").reason).to eq("only_eligible_provider")
  end

  it "evaluates provider-specific profiles", :aggregate_failures do
    policy = Routing::Policy.new(
      "strategies" => {},
      "profiles" => {
        "conversion_only" => { "strategies" => { "conversion" => { "weight" => 1 } } },
        "cascade_only" => { "strategies" => { "cascade_priority" => { "weight" => 1 } } }
      },
      "provider_profiles" => { "vipay" => "cascade_only", "payflow" => "conversion_only" }
    )
    ranking = described_class.call(
      eligible: [vipay, payflow], operation: build_operation, snapshot: snapshot, policy: policy
    )

    expect(ranking.scores.fetch("vipay").contributions.map(&:name)).to eq(["cascade_priority"])
    expect(ranking.scores.fetch("payflow").contributions.map(&:name)).to eq(["conversion"])
  end

  it "uses post-assignment share improvement and reports strategy disagreement", :aggregate_failures do
    policy = Routing::Policy.new(
      "strategies" => {
        "conversion" => { "enabled" => true, "weight" => 0.5 },
        "count_share" => { "enabled" => true, "weight" => 0.5 }
      }
    )
    state = empty_snapshot(
      counts: { "vipay" => 2, "payflow" => 2 },
      count_targets: { "vipay" => 60, "payflow" => 40 },
      providers: [vipay, payflow]
    )
    ranking = described_class.call(
      eligible: [vipay, payflow], operation: build_operation, snapshot: state, policy: policy
    )

    expect(ranking.scores.fetch("vipay").contribution("count_share").score).to eq(1.0)
    expect(ranking.conflicts.map(&:kind)).to include("goal_disagreement")
  end
end
