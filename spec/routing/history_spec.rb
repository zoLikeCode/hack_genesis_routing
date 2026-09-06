# frozen_string_literal: true

require "tmpdir"

RSpec.describe Routing::History do
  describe ".load" do
    subject(:history) { described_class.load(File.join(SPEC_ROOT, "data/operations_history.csv")) }

    it "aggregates public history by provider" do
      expect(history.names).to include("vipay", "payflow", "quickpay")
    end

    it "counts vipay rows" do
      expect(history["vipay"].fetch("count")).to be_positive
    end

    it "uses approved payouts for historical volume" do
      expect(history["vipay"].fetch("volume")).to be < history["vipay"].fetch("attempted_volume")
    end

    it "computes vipay conversion in [0, 1]" do
      expect(history["vipay"].fetch("conversion")).to be_between(0, 1)
    end

    it "computes vipay average latency" do
      expect(history["vipay"].fetch("avg_latency_sec")).to be_positive
    end

    it "keeps unknown latency as nil and excludes it from the average", :aggregate_failures do
      local_history = described_class.load(history_with_unknown_latency_path)

      expect(local_history.observations.first.latency_sec).to be_nil
      expect(local_history["vipay"].fetch("avg_latency_sec")).to eq(20.0)
    end

    it "builds a bounded conversion estimate from preceding rows", :aggregate_failures do
      quality = history.quality(provider: public_provider("vipay"), operation: build_operation(bank: "sberbank"))

      expect(quality).to have_attributes(scope: "provider", sample_size: 12)
      expect(quality.score).to be_between(0, 1)
      expect(quality.initial_approval_rate).to be_between(0, 1)
      expect(quality.initial_timeout_rate).to be_between(0, 1)
    end

    it "uses the provider prior when a provider has no history", :aggregate_failures do
      provider = build_provider(payment_system: "newpay", conversion_24h: 0.80)
      quality = history.quality(provider: provider, operation: build_operation)

      expect(quality).to have_attributes(scope: "prior", sample_size: 0, score: 0.8)
    end

    it "does not use observations from the operation future" do
      observations = [
        observation(id_time: "2026-07-30T09:00:00+03:00", status: "rejected"),
        observation(id_time: "2026-07-30T10:00:00+03:00", status: "approved")
      ]
      local_history = described_class.new({}, observations: observations)

      quality = local_history.quality(provider: build_provider, operation: build_operation)

      expect(quality.sample_size).to eq(1)
    end

    it "ignores rows that violate the provider current bank rules" do
      local_history = described_class.new(
        {},
        observations: [observation(id_time: "2026-07-30T09:00:00+03:00", status: "approved", bank: "alfa")]
      )

      quality = local_history.quality(provider: build_provider, operation: build_operation)

      expect(quality).to have_attributes(scope: "prior", sample_size: 0)
    end

    it "raises InvalidInputError when the file is missing" do
      expect { described_class.load("missing.csv") }.to raise_error(Routing::InvalidInputError)
    end

    it "raises InvalidInputError when a numeric field is invalid" do
      expect { described_class.load(invalid_history_path) }.to raise_error(Routing::InvalidInputError)
    end

    def invalid_history_path
      path = File.join(Dir.mktmpdir, "bad.csv")
      File.write(path, "operation_id,amount,payment_system,status,latency_sec\nop_1,not-a-number,vipay,approved,1\n")
      path
    end

    def history_with_unknown_latency_path
      path = File.join(Dir.mktmpdir, "unknown-latency.csv")
      File.write(path, <<~CSV)
        operation_id,amount,payment_system,status,latency_sec,created_at,bank
        op_1,1000,vipay,approved,,2026-07-30T09:00:00+03:00,sberbank
        op_2,1000,vipay,rejected,20,2026-07-30T09:01:00+03:00,sberbank
      CSV
      path
    end

    def public_provider(name)
      Routing::ProviderPool.load(File.join(SPEC_ROOT, "data/providers.json")).fetch(name)
    end

    def observation(id_time:, status:, bank: "sberbank")
      Routing::History::Observation.new(
        operation_id: "op_hist_#{id_time}",
        provider_name: "vipay",
        created_at: Time.iso8601(id_time),
        amount: 15_000,
        bank: bank,
        initial_status: status,
        status: status,
        latency_sec: 30,
        attempted_at: Time.iso8601(id_time),
        admission_sequence: nil,
        completed_at: Time.iso8601(id_time)
      )
    end
  end
end
