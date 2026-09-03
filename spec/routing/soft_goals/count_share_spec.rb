# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::CountShare do
  subject(:contribution) { described_class.call(provider, build_operation, snapshot) }

  let(:provider) { build_provider }
  let(:snapshot) { empty_snapshot }

  it "boosts a provider below its count target" do
    expect(contribution).to have_attributes(score: 0.40, reason: "count_share_deficit")
  end

  it "penalizes a provider above its count target" do
    over = empty_snapshot(counts: { "vipay" => 80, "payflow" => 20 })
    result = described_class.call(provider, build_operation, over)
    expect(result).to have_attributes(score: -0.40, reason: "count_share_over_target")
  end
end
