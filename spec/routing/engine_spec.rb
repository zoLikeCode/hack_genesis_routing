# frozen_string_literal: true

RSpec.describe Routing::Engine do
  describe ".call" do
    let(:policy) { Routing::Policy.load(File.join(SPEC_ROOT, "config/routing_policy.yml")) }

    it "covers every public-queue operation" do
      expect(public_decisions.map(&:operation_id)).to eq(public_queue.map(&:id))
    end

    it "matches deterministic public-queue providers" do
      required = public_reference.fetch("deterministic_cases").to_h do |row|
        [row.fetch("operation_id"), row.fetch("required_provider")]
      end
      actual = public_decisions.to_h { |decision| [decision.operation_id, decision.selected_provider] }
      expect(actual.slice(*required.keys)).to eq(required)
    end

    it "cascades to the next eligible provider after a simulated refusal" do
      expect(cascade_decision.selected_provider).to eq("payflow")
    end

    it "records a simulated skip then a selected attempt" do
      triples = cascade_decision.attempts.map { |attempt| [attempt.provider, attempt.decision, attempt.reason] }
      expect(triples).to include(%w[vipay skipped simulated_rejected], %w[payflow selected only_eligible_provider])
    end

    it "selects the fallback provider when no primary is eligible" do
      expect(fallback_decision.selected_provider).to eq("spacepayments")
    end

    it "marks a last-resort attempt as fallback_selected" do
      expect(fallback_decision.attempts.map(&:reason)).to include("fallback_selected")
    end

    def cascade_decision
      described_class.call(
        operations: [build_operation],
        providers: two_primary_pool,
        policy: build_policy,
        simulator: sequenced_simulator(%w[rejected approved])
      ).first
    end

    def fallback_decision
      described_class.call(
        operations: [build_operation],
        providers: fallback_only_pool,
        policy: build_policy,
        simulator: sequenced_simulator(%w[approved])
      ).first
    end

    def public_decisions
      described_class.call(
        operations: public_queue,
        providers: public_pool,
        policy: policy,
        simulator: sequenced_simulator(Array.new(public_queue.size, "approved"))
      )
    end

    def public_pool
      Routing::ProviderPool.load(File.join(SPEC_ROOT, "data/providers.json"))
    end

    def public_queue
      Routing::Operation.load_queue(File.join(SPEC_ROOT, "data/operations_queue_10.json"))
    end

    def public_reference
      Routing::JsonFile.read(File.join(SPEC_ROOT, "data/reference_decisions.json"))
    end

    def two_primary_pool
      Routing::ProviderPool.new(
        [
          build_provider,
          build_provider(payment_system: "payflow", traffic_percentage: 35, priority: 2,
                         conversion_24h: 0.91, volume_share_pct: 20, banks: %w[sberbank alfa]),
          fallback_provider
        ]
      )
    end

    def fallback_only_pool
      Routing::ProviderPool.new(
        [
          build_provider(limit_amount_max: 1),
          build_provider(payment_system: "payflow", traffic_percentage: 35, limit_amount_max: 1),
          fallback_provider
        ]
      )
    end

    def fallback_provider
      build_provider(payment_system: "spacepayments", traffic_percentage: 0, limit_amount_min: nil,
                     limit_amount_max: nil, daily_amount_limit: nil, in_progress_count_limit: nil,
                     in_progress_amount_limit: nil, banks: [], conversion_24h: 1.0)
    end

    def sequenced_simulator(results)
      queue = results.dup
      simulator = Object.new
      simulator.define_singleton_method(:call) do |_provider|
        { result: queue.shift || "approved", latency_sec: 30 }
      end
      simulator
    end
  end
end
