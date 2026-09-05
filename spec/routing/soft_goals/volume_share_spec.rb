# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::VolumeShare do
  it "uses the current amount in each candidate projection", :aggregate_failures do
    vipay = build_provider(volume_share_pct: 50)
    payflow = build_provider(payment_system: "payflow", volume_share_pct: 50)
    snapshot = empty_snapshot(
      volumes: { "vipay" => 80_000, "payflow" => 20_000 },
      volume_targets: { "vipay" => 50, "payflow" => 50 }
    )
    scores = described_class.score_all(
      candidates: [vipay, payflow], operation: build_operation(amount: 20_000), snapshot: snapshot
    )

    expect(scores.fetch("payflow").score).to be_within(1e-6).of(0.972222)
    expect(scores.fetch("vipay").score).to be_within(1e-6).of(0.888889)
  end

  it "returns equal neutral scores when candidates change error equally" do
    candidates = [build_provider, build_provider(payment_system: "payflow")]
    snapshot = empty_snapshot(
      volumes: { "vipay" => 50, "payflow" => 50 },
      volume_targets: { "vipay" => 50, "payflow" => 50 }
    )
    scores = described_class.score_all(
      candidates: candidates, operation: build_operation(amount: 10), snapshot: snapshot
    )

    expect(scores.values.map(&:score)).to all(be_within(1e-6).of(0.997934))
  end
end
