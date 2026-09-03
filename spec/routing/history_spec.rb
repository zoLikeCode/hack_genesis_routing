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

    it "computes vipay conversion in [0, 1]" do
      expect(history["vipay"].fetch("conversion")).to be_between(0, 1)
    end

    it "computes vipay average latency" do
      expect(history["vipay"].fetch("avg_latency_sec")).to be_positive
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
  end
end
