# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::Conversion do
  subject(:contribution) { described_class.call(build_provider, build_operation, empty_snapshot) }

  it "uses conversion_24h as the score" do
    expect(contribution).to have_attributes(score: 0.87, reason: "higher_conversion")
  end

  it "returns a neutral score when conversion_24h is nil" do
    result = described_class.call(build_provider(conversion_24h: nil), build_operation, empty_snapshot)
    expect(result).to have_attributes(score: 0.0, reason: "soft_goal_neutral")
  end
end
