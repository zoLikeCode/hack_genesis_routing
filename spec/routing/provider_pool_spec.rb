# frozen_string_literal: true

RSpec.describe Routing::ProviderPool do
  subject(:pool) { described_class.new([vipay, payflow]) }

  let(:vipay) { build_provider }
  let(:payflow) { build_provider(payment_system: "payflow", traffic_percentage: 35) }
  let(:operation) { build_operation }

  describe ".load" do
    it "reads providers.json" do
      loaded = described_class.load(File.join(SPEC_ROOT, "data/providers.json"))
      expect(loaded.map(&:name)).to eq(%w[vipay payflow quickpay spacepayments])
    end
  end

  describe "#reserve!" do
    it "mutates the pooled provider instance" do
      pool.reserve!(vipay, operation)
      expect(pool.fetch("vipay").in_progress_count).to eq(1)
    end
  end

  describe "state after mutation" do
    it "allows a provider before in-progress exhaustion" do
      tight = build_provider(in_progress_count: 1, in_progress_count_limit: 2)
      expect(Routing::HardConstraints::InProgress.call(tight, operation)).to be_ok
    end

    it "skips a provider once in-progress count is exhausted" do
      tight = build_provider(in_progress_count: 1, in_progress_count_limit: 2)
      described_class.new([tight]).reserve!(tight, operation)
      expect(Routing::HardConstraints::InProgress.call(tight, operation).reason).to eq("in_progress_count_exceeded")
    end

    it "allows a provider before the daily cap is committed" do
      tight = build_provider(daily_approved_amount: 900, daily_amount_limit: 1_000)
      expect(Routing::HardConstraints::DailyLimit.call(tight, build_operation(amount: 50))).to be_ok
    end

    it "skips a provider once the daily limit is committed" do
      tight = build_provider(daily_approved_amount: 900, daily_amount_limit: 1_000)
      described_class.new([tight]).commit_approved!(tight, 100)
      expect(Routing::HardConstraints::DailyLimit.call(tight, build_operation(amount: 50)).reason)
        .to eq("daily_limit_exceeded")
    end
  end
end
