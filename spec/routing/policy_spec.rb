# frozen_string_literal: true

RSpec.describe Routing::Policy do
  let(:profile_providers) do
    {
      "reliable_history" => "vipay", "controlled_share" => "payflow",
      "capacity_obligation" => "quickpay"
    }
  end

  describe ".load" do
    subject(:policy) { described_class.load(File.join(SPEC_ROOT, "config/routing_policy.yml")) }

    it "loads the simplified conversion metric configuration", :aggregate_failures do
      expect(policy.metrics.max_observations).to eq(50)
      expect(policy.metrics.lookback_seconds).to eq(24 * 60 * 60)
      expect(policy.metrics.prior_strength).to eq(10.0)
      expect(policy.metrics.default_conversion_prior).to eq(0.5)
      expect(policy.metrics.segment_min_size).to eq(10)
    end

    it "keeps provider profile assignments", :aggregate_failures do
      expect(policy.profile_for("vipay")).to eq("reliable_history")
      expect(policy.profile_for("payflow")).to eq("controlled_share")
      expect(policy.profile_for("quickpay")).to eq("capacity_obligation")
    end

    it "normalizes every active profile independently" do
      %w[balanced reliable_history controlled_share capacity_obligation].each do |name|
        provider = profile_providers.fetch(name, "unassigned")
        expect(policy.strategy_weights_for(provider).values.sum).to be_within(1e-10).of(1.0)
      end
    end

    it "loads inclusive amount-band preferences", :aggregate_failures do
      expect(policy.amount_band_score("payflow", 50_000)).to eq(1.0)
      expect(policy.amount_band_score("vipay", 50_001)).to eq(1.0)
      expect(policy.amount_band_score("quickpay", 100_001)).to eq(1.0)
    end

    it "loads status-check settings" do
      expect(policy.status_check).to include("enabled" => true, "initial_delay_sec" => 5, "max_attempts" => 5)
    end
  end

  it "normalizes enabled direct strategies", :aggregate_failures do
    policy = described_class.new(
      "strategies" => {
        "conversion" => { "enabled" => true, "weight" => 3 },
        "load_balance" => { "enabled" => true, "weight" => 1 }
      }
    )

    expect(policy.weight_for("conversion")).to eq(0.75)
    expect(policy.weight_for("load_balance")).to eq(0.25)
  end

  it "validates share targets before routing starts" do
    policy = described_class.new(
      "strategies" => { "count_share" => { "enabled" => true, "weight" => 1 } }
    )
    providers = Routing::ProviderPool.new([build_provider(traffic_percentage: 60)])

    expect { policy.validate_provider_targets!(providers) }
      .to raise_error(Routing::InvalidInputError, /sum to 100/)
  end

  it "rejects zero active strategy weight" do
    expect do
      described_class.new("strategies" => { "conversion" => { "enabled" => true, "weight" => 0 } })
    end.to raise_error(Routing::InvalidInputError, /positive when enabled/)
  end

  it "rejects individual mode without an enabled strategy" do
    expect { described_class.new("strategies" => {}) }
      .to raise_error(Routing::InvalidInputError, /must enable at least one strategy/)
  end

  it "rejects profile mode mixed with a direct strategy" do
    expect do
      described_class.new(
        "active_profile" => "only",
        "strategies" => { "conversion" => { "enabled" => true, "weight" => 1 } },
        "profiles" => { "only" => { "strategies" => { "conversion" => { "weight" => 1 } } } }
      )
    end.to raise_error(Routing::InvalidInputError, /active_profile cannot be used/)
  end

  it "rejects removed metric and health settings clearly" do
    expect do
      described_class.new(
        "metrics" => { "multipliers" => { "health" => { "enabled" => true } } },
        "strategies" => { "conversion" => { "enabled" => true, "weight" => 1 } }
      )
    end.to raise_error(Routing::InvalidInputError, /unknown keys: multipliers/)
  end

  it "rejects malformed amount bands" do
    expect do
      described_class.new(
        "amount_bands" => [{ "max" => 50_000, "providers" => ["vipay"] }],
        "strategies" => { "amount_band" => { "enabled" => true, "weight" => 1 } }
      )
    end.to raise_error(Routing::InvalidInputError, /final amount band/)
  end

  describe "status_check" do
    it "uses safe defaults when the section is omitted" do
      policy = described_class.new(
        "strategies" => { "conversion" => { "enabled" => true, "weight" => 1 } }
      )

      expect(policy.status_check).to eq(
        "enabled" => true, "initial_delay_sec" => 5,
        "retry_delays_sec" => [5, 15, 30, 60], "max_attempts" => 5
      )
    end

    it "rejects an empty retry schedule" do
      expect do
        described_class.new(
          "status_check" => { "retry_delays_sec" => [] },
          "strategies" => { "conversion" => { "enabled" => true, "weight" => 1 } }
        )
      end.to raise_error(Routing::InvalidInputError, /non-empty list/)
    end
  end

  describe "circuit_breaker" do
    it "uses production-safe defaults" do
      policy = described_class.new(
        "strategies" => { "conversion" => { "enabled" => true, "weight" => 1 } }
      )

      expect(policy.circuit_breaker).to eq(
        "enabled" => true, "unresolved_count_limit" => 5, "unresolved_amount_limit" => 500_000
      )
    end

    it "rejects invalid unresolved thresholds" do
      expect do
        described_class.new(
          "circuit_breaker" => { "unresolved_count_limit" => 0 },
          "strategies" => { "conversion" => { "enabled" => true, "weight" => 1 } }
        )
      end.to raise_error(Routing::InvalidInputError, /unresolved_count_limit/)
    end
  end
end
