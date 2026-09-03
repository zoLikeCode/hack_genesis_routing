# frozen_string_literal: true

RSpec.describe Routing::HardConstraints::Status do
  let(:operation) { build_operation }

  it "passes an active provider" do
    expect(described_class.call(build_provider, operation)).to be_ok
  end

  it "skips an inactive provider" do
    result = described_class.call(build_provider(status: "disabled"), operation)
    expect(result).to be_skipped.and have_attributes(reason: "provider_inactive", details: "disabled != active")
  end
end
