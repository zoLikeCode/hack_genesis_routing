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

    it "leaves active_profile nil in individual mode" do
      expect(policy.active_profile).to be_nil
    end

    it "enables count_share in individual mode" do
      expect(policy.enabled?("count_share")).to be(true)
    end

    it "reads simulation_seed from routing_policy.yml" do
      expect(policy.simulation_seed).to eq(42)
    end

    it "reads a null default RPM limit from routing_policy.yml" do
      expect(policy.default_requests_per_minute_limit).to be_nil
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

    let(:mixed) do
      described_class.new(
        "strategies" => {
          "count_share" => { "enabled" => true, "weight" => 1.0 },
          "conversion" => { "enabled" => false, "weight" => 1.0 }
        }
      )
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

    it "defaults simulation_seed to 42" do
      expect(described_class.new({}).simulation_seed).to eq(42)
    end

    it "reads default_requests_per_minute_limit from hard_constraints" do
      policy = described_class.new("hard_constraints" => { "default_requests_per_minute_limit" => 7 })
      expect(policy.default_requests_per_minute_limit).to eq(7)
    end

    it "keeps the weight of an enabled individual strategy" do
      expect(mixed.weight_for("count_share")).to eq(1.0)
    end

    it "zeros the weight of a disabled individual strategy" do
      expect(mixed.weight_for("conversion")).to eq(0)
    end
  end

  describe "profiles" do
    subject(:policy) { described_class.new(profile_policy_data) }

    let(:profile_policy_data) do
      {
        "active_profile" => "conversion_first",
        "strategies" => {
          "count_share" => { "enabled" => false, "weight" => 0.30 },
          "volume_share" => { "enabled" => false, "weight" => 0.20 }
        },
        "profiles" => {
          "conversion_first" => {
            "strategies" => {
              "conversion" => { "weight" => 0.75 },
              "count_share" => { "weight" => 0.25 }
            }
          }
        }
      }
    end

    it "uses conversion weight from the selected profile" do
      expect(policy.weight_for("conversion")).to eq(0.75)
    end

    it "uses count_share weight from the selected profile" do
      expect(policy.weight_for("count_share")).to eq(0.25)
    end

    it "disables strategies that are not in the selected profile" do
      expect(policy.enabled?("volume_share")).to be(false)
    end

    it "exposes the selected profile" do
      expect(policy.active_profile).to eq("conversion_first")
    end

    it "rejects a profile together with an enabled individual strategy" do
      profile_policy_data["strategies"]["count_share"]["enabled"] = true

      expect { policy }.to raise_error(
        Routing::InvalidInputError,
        "active_profile cannot be used while an individual strategy is enabled"
      )
    end

    it "rejects an unknown selected profile" do
      profile_policy_data["active_profile"] = "missing"

      expect { policy }.to raise_error(Routing::InvalidInputError, "unknown active_profile missing")
    end

    it "rejects an empty profile" do
      profile_policy_data["profiles"]["conversion_first"]["strategies"] = {}

      expect { policy }.to raise_error(
        Routing::InvalidInputError,
        "profiles.conversion_first.strategies must not be empty"
      )
    end
  end
end
