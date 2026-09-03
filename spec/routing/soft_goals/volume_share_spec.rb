# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::VolumeShare do
  subject(:contribution) { described_class.call(provider, build_operation, snapshot) }

  let(:provider) { build_provider }
  let(:snapshot) { empty_snapshot }

  it "boosts a provider below its volume target" do
    expect(contribution).to have_attributes(score: 0.50, reason: "volume_share_deficit")
  end

  it "penalizes a provider above its volume target" do
    over = empty_snapshot(volumes: { "vipay" => 80, "payflow" => 20 })
    result = described_class.call(provider, build_operation, over)
    expect(result).to have_attributes(score: be_within(0.001).of(-0.30), reason: "volume_share_over_target")
  end

  it "returns a neutral score when volume_share_pct is nil" do
    result = described_class.call(build_provider(volume_share_pct: nil), build_operation, snapshot)
    expect(result).to have_attributes(score: 0.0, reason: "soft_goal_neutral")
  end
end
