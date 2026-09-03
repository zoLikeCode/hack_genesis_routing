# frozen_string_literal: true

RSpec.describe Routing::Selector do
  it "returns ranking.preferred" do
    vipay = build_provider
    ranking = Routing::SoftGoals::Ranking.new(
      ordered: [vipay], scores: {}, conflicts: [], notes: []
    )
    expect(described_class.call(ranking: ranking, operation: build_operation, policy: build_policy)).to eq(vipay)
  end
end
