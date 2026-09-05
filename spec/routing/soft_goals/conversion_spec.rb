# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::Conversion do
  it "combines immutable initial outcomes with the published prior", :aggregate_failures do
    provider = build_provider(conversion_24h: 0.8)
    history = Routing::History.new(
      {},
      observations: [
        build_observation(status: "approved"),
        build_observation(operation_id: "timeout", initial_status: "expired", status: "approved")
      ]
    )
    contribution = described_class.call(provider, build_operation, empty_snapshot(history: history))

    expect(contribution.score).to be_within(0.0001).of(9.0 / 12)
    expect(contribution.details).to include("source=provider_history", "n=2")
  end

  it "uses the configured neutral prior when published conversion is absent" do
    result = described_class.call(build_provider(conversion_24h: nil), build_operation, empty_snapshot)

    expect(result.score).to eq(0.5)
  end
end
