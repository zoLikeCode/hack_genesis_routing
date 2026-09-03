# frozen_string_literal: true

RSpec.describe Routing::Policy do
  describe ".load" do
    subject(:policy) { described_class.load(File.join(SPEC_ROOT, "config/routing_policy.yml")) }

    it "reads count_share weight from routing_policy.yml" do
      expect(policy.weight_for("count_share")).to eq(0.30)
    end

    it "reads financial_obligation weight from routing_policy.yml" do
      expect(policy.weight_for("financial_obligation")).to eq(0.05)
    end

    it "raises InvalidInputError when the file is missing" do
      expect { described_class.load("missing-policy.yml") }.to raise_error(Routing::InvalidInputError)
    end

    it "raises InvalidInputError when YAML is invalid" do
      path = File.join(SPEC_ROOT, "spec/support/fixtures.rb")
      expect { described_class.load(path) }.to raise_error(Routing::InvalidInputError)
    end
  end

  describe "#weight_for" do
    let(:disabled) do
      described_class.new("strategies" => { "count_share" => { "enabled" => false, "weight" => 0.30 } })
    end

    it "returns 0 when the strategy is disabled" do
      expect(disabled.weight_for("count_share")).to eq(0)
    end

    it "treats a disabled strategy as not enabled" do
      expect(disabled.enabled?("count_share")).to be(false)
    end

    it "returns 0 for an unknown strategy" do
      expect(described_class.new({}).weight_for("missing")).to eq(0)
    end
  end
end
