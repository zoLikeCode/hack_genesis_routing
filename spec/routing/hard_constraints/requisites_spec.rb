# frozen_string_literal: true

RSpec.describe Routing::HardConstraints::Requisites do
  let(:operation) { build_operation }

  it "passes when requisites are available" do
    expect(described_class.call(build_provider(available_requisites: 1), operation)).to be_ok
  end

  it "skips when no requisites remain" do
    result = described_class.call(build_provider(available_requisites: 0), operation)
    expect(result).to be_skipped.and have_attributes(reason: "no_requisites", details: "available_requisites == 0")
  end
end
