# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::AmountBand do
  let(:policy) { Routing::Policy.load(File.join(SPEC_ROOT, "config/routing_policy.yml")) }

  it "uses configured preferences at exact inclusive boundaries", :aggregate_failures do
    payflow = build_provider(payment_system: "payflow")
    vipay = build_provider(payment_system: "vipay")

    expect(described_class.call(payflow, build_operation(amount: 50_000), empty_snapshot, policy).score).to eq(1.0)
    expect(described_class.call(vipay, build_operation(amount: 50_001), empty_snapshot, policy).score).to eq(1.0)
  end

  it "prefers quickpay above one hundred thousand" do
    quickpay = build_provider(payment_system: "quickpay")
    vipay = build_provider(payment_system: "vipay")
    operation = build_operation(amount: 100_001)

    expect(described_class.call(quickpay, operation, empty_snapshot, policy).score)
      .to be > described_class.call(vipay, operation, empty_snapshot, policy).score
  end
end
