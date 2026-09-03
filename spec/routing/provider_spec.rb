# frozen_string_literal: true

RSpec.describe Routing::Provider do
  subject(:provider) { build_provider }

  describe "#reserve!" do
    let(:at) { Time.iso8601("2026-07-30T09:05:00+03:00") }

    it "increments in-progress load" do
      provider.reserve!(15_000, at: at)
      expect(provider).to have_attributes(in_progress_count: 1, in_progress_amount: 15_000)
    end

    it "records the request on the RPM deque" do
      provider.reserve!(15_000, at: at)
      expect(provider.request_count_at(at)).to eq(1)
    end
  end

  describe "#release!" do
    let(:at) { Time.iso8601("2026-07-30T09:05:00+03:00") }

    it "decrements in-progress load" do
      provider.reserve!(15_000, at: at)
      provider.release!(15_000)
      expect(provider).to have_attributes(in_progress_count: 0, in_progress_amount: 0)
    end

    it "rejects release without a matching reserve" do
      expect { provider.release!(1) }.to raise_error(Routing::InvariantError)
    end
  end

  describe "#commit_approved!" do
    it "adds approved volume to the daily total" do
      provider.commit_approved!(15_000)
      expect(provider.daily_approved_amount).to eq(15_000)
    end
  end

  describe "#primary?" do
    it "excludes the fallback provider" do
      fallback = build_provider(payment_system: "spacepayments", traffic_percentage: 0)
      expect(fallback.primary?(fallback: "spacepayments")).to be(false)
    end

    it "excludes zero-traffic providers" do
      expect(build_provider(traffic_percentage: 0).primary?(fallback: "spacepayments")).to be(false)
    end
  end

  describe "soft-goal fields" do
    subject(:loaded) { Routing::ProviderPool.load(File.join(SPEC_ROOT, "data/providers.json")).fetch("vipay") }

    it "loads priority from providers.json" do
      expect(loaded.priority).to eq(1)
    end

    it "loads conversion_24h from providers.json" do
      expect(loaded.conversion_24h).to eq(0.87)
    end

    it "loads volume_share_pct from providers.json" do
      expect(loaded.volume_share_pct).to eq(50)
    end

    it "loads requests_per_minute_limit from providers.json" do
      expect(loaded.requests_per_minute_limit).to eq(15)
    end

    it "loads daily_turnover_min from providers.json" do
      expect(loaded.daily_turnover_min).to eq(3_000_000)
    end

    it "loads daily_turnover_max from providers.json" do
      expect(loaded.daily_turnover_max).to eq(4_500_000)
    end

    it "loads avg_latency_sec from providers.json" do
      expect(loaded.avg_latency_sec).to eq(38)
    end
  end
end
