# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::CascadePriority do
  it "spreads unique priority levels uniformly and keeps ties equal" do
    providers = [
      build_provider(payment_system: "a", priority: 1),
      build_provider(payment_system: "b", priority: 2),
      build_provider(payment_system: "c", priority: 2),
      build_provider(payment_system: "d", priority: nil)
    ]
    scores = described_class.score_all(providers: providers)

    expect(scores).to eq("a" => 1.0, "b" => 0.5, "c" => 0.5, "d" => 0.0)
  end

  it "returns one when the pool has one priority level" do
    providers = [build_provider(payment_system: "a", priority: 1), build_provider(payment_system: "b", priority: 1)]

    expect(described_class.score_all(providers: providers).values).to eq([1.0, 1.0])
  end
end
