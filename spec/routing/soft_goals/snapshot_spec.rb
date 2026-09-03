# frozen_string_literal: true

RSpec.describe Routing::SoftGoals::Snapshot do
  describe ".from_providers" do
    subject(:snapshot) { described_class.from_providers([vipay, payflow]) }

    let(:vipay) { build_provider(daily_approved_amount: 3_200_000, volume_share_pct: 50) }
    let(:payflow) do
      build_provider(payment_system: "payflow", daily_approved_amount: 2_900_000, volume_share_pct: 20)
    end

    it "starts session counts at zero" do
      expect(snapshot.count_share_pct("vipay")).to eq(0.0)
    end

    it "seeds vipay volume from daily_approved_amount" do
      expect(snapshot.volume_share_pct("vipay")).to be_within(0.01).of(52.46)
    end

    it "seeds payflow volume from daily_approved_amount" do
      expect(snapshot.volume_share_pct("payflow")).to be_within(0.01).of(47.54)
    end
  end

  describe "#record!" do
    subject(:snapshot) { described_class.new(counts: { "vipay" => 1 }, volumes: { "vipay" => 10_000 }) }

    before { snapshot.record!("payflow", 30_000) }

    it "updates count percentages" do
      expect(snapshot.count_share_pct("vipay")).to eq(50.0)
    end

    it "updates volume percentages" do
      expect(snapshot.volume_share_pct("payflow")).to eq(75.0)
    end
  end
end
