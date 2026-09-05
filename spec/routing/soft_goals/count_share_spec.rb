# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::CountShare do
  it "prefers the assignment that most improves the complete target distribution", :aggregate_failures do
    vipay = build_provider(traffic_percentage: 60)
    payflow = build_provider(payment_system: "payflow", traffic_percentage: 40)
    snapshot = empty_snapshot(
      counts: { "vipay" => 2, "payflow" => 2 },
      count_targets: { "vipay" => 60, "payflow" => 40 }
    )
    scores = described_class.score_all(candidates: [vipay, payflow], snapshot: snapshot)

    expect(scores.fetch("vipay").score).to eq(1.0)
    expect(scores.fetch("payflow").score).to be_within(1e-10).of(0.96)
    expect(scores.fetch("vipay").after_error).to be < scores.fetch("payflow").after_error
  end

  it "requires enabled targets to total one hundred percent" do
    snapshot = empty_snapshot(count_targets: { "vipay" => 60 })

    expect do
      described_class.score_all(candidates: [build_provider], snapshot: snapshot)
    end.to raise_error(Routing::InvalidInputError, /sum to 100/)
  end

  it "rejects percentages outside the valid range" do
    snapshot = empty_snapshot(count_targets: { "vipay" => 120, "payflow" => 0 })

    expect do
      described_class.score_all(candidates: [build_provider], snapshot: snapshot)
    end.to raise_error(Routing::InvalidInputError, /percentages in \[0, 100\]/)
  end
end
