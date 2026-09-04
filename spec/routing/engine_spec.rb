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

    it "records cascade refusals on the rejected provider window", :aggregate_failures do
      providers = two_primary_pool
      engine = described_class.new(
        [build_operation],
        providers,
        build_policy("cascade_priority" => { "enabled" => true, "weight" => 1.0 }),
        sequenced_simulator(%w[rejected approved])
      )
      engine.call

      expect(engine.state.metrics.observations_for("vipay").map(&:status)).to eq(%w[rejected])
      expect(engine.state.metrics.observations_for("payflow").map(&:status)).to eq(%w[approved])
    end

    it "selects the fallback provider when no primary is eligible" do
      expect(fallback_decision.selected_provider).to eq("spacepayments")
    end

    it "marks a last-resort attempt as fallback_selected" do
      expect(fallback_decision.attempts.map(&:reason)).to include("fallback_selected")
    end

    it "rolls a rejected final fallback out of traffic share", :aggregate_failures do
      decisions = rejected_fallback_decisions

      expect(decisions.map(&:selected_provider)).to eq(%w[spacepayments vipay payflow])
      expect(decisions.first.simulated_result).to eq("rejected")
    end

    it "keeps a timed-out provider selected without starting fallback", :aggregate_failures do
      providers = two_primary_pool
      engine = described_class.new(
        [build_operation],
        providers,
        build_policy("cascade_priority" => { "enabled" => true, "weight" => 1.0 }),
        sequenced_simulator(%w[expired approved])
      )

      decision = engine.call.first

      expect(decision).to have_attributes(selected_provider: "vipay", simulated_result: "expired")
      expect(decision.attempts.count { |attempt| attempt.decision == "selected" }).to eq(1)
      expect(decision.attempts.last.details).to include("timeout reservation retained")
      expect(engine.state.reservations.first.status).to eq("timed_out")
      expect(providers.fetch("vipay").in_progress_count).to eq(1)
    end

    it "applies a late timeout cancellation only to current state", :aggregate_failures do
      providers = two_primary_pool
      engine = described_class.new(
        [build_operation],
        providers,
        build_policy("cascade_priority" => { "enabled" => true, "weight" => 1.0 }),
        sequenced_simulator(%w[expired])
      )
      decision = engine.call.first

      engine.state.resolve_timeout!(
        operation_id: decision.operation_id,
        provider_name: decision.selected_provider,
        result: "cancelled"
      )

      expect(decision.simulated_result).to eq("expired")
      expect(engine.state.snapshot.soft_goals.total_count).to eq(0)
      expect(providers.fetch("vipay").in_progress_count).to eq(0)
    end

    it "runs due status checks before routing the next online operation", :aggregate_failures do
      providers = two_primary_pool
      client = status_client(call_results: %w[expired approved], status_results: %w[cancelled])
      policy = Routing::Policy.new(
        "status_check" => status_check_config,
        "strategies" => { "cascade_priority" => { "enabled" => true, "weight" => 1.0 } }
      )
      operations = [
        build_operation(operation_id: "timed_out"),
        build_operation(operation_id: "next", created_at: "2026-07-30T09:06:00+03:00")
      ]

      engine = described_class.new(operations, providers, policy, client)
      decisions = engine.call

      expect(decisions.first).to have_attributes(selected_provider: "vipay", simulated_result: "expired")
      expect(decisions.last).to have_attributes(selected_provider: "vipay", simulated_result: "approved")
      expect(client.status_requests).to eq([["timed_out", "timed_out:vipay"]])
      expect(engine.status_checker.tasks.first).to have_attributes(status: "resolved", last_result: "rejected")
      reservation = engine.state.reservation_for(operation_id: "timed_out", provider_name: "vipay")
      expect(reservation.status).to eq("rejected")
    end

    it "settles a timeout from the end of the batch", :aggregate_failures do
      providers = two_primary_pool
      client = status_client(call_results: %w[expired], status_results: %w[approved])
      policy = Routing::Policy.new(
        "status_check" => status_check_config,
        "strategies" => { "cascade_priority" => { "enabled" => true, "weight" => 1.0 } }
      )

      engine = described_class.new([build_operation], providers, policy, client)
      decision = engine.call.first

      expect(decision).to have_attributes(selected_provider: "vipay", simulated_result: "expired")
      expect(engine.state.reservations.first.status).to eq("approved")
      expect(engine.status_checker.tasks.first).to have_attributes(status: "resolved", last_result: "approved")
      expect(providers.fetch("vipay")).to have_attributes(in_progress_count: 0, daily_reserved_amount: 0)
    end

    it "rolls back a late refusal without starting fallback", :aggregate_failures do
      providers = two_primary_pool
      client = status_client(call_results: %w[expired], status_results: %w[cancelled])
      policy = Routing::Policy.new(
        "status_check" => status_check_config,
        "strategies" => { "cascade_priority" => { "enabled" => true, "weight" => 1.0 } }
      )

      engine = described_class.new([build_operation], providers, policy, client)
      decision = engine.call.first

      expect(decision.attempts.count { |attempt| attempt.decision == "selected" }).to eq(1)
      expect(decision.selected_provider).to eq("vipay")
      expect(engine.state.reservations.first.status).to eq("rejected")
      expect(providers.fetch("vipay")).to have_attributes(
        in_progress_count: 0, in_progress_amount: 0, daily_reserved_amount: 0
      )
    end

    it "records eligible providers that lost the soft-score comparison" do
      decision = described_class.call(
        operations: [build_operation],
        providers: two_primary_pool,
        policy: build_policy,
        simulator: sequenced_simulator(%w[approved])
      ).first

      expect(decision.attempts).to include(
        have_attributes(decision: "skipped", reason: "lower_soft_score")
      )
    end

    it "adds latency across rejected cascade attempts" do
      decision = described_class.call(
        operations: [build_operation],
        providers: two_primary_pool,
        policy: build_policy,
        simulator: outcome_simulator(
          [
            { result: "rejected", latency_sec: 11 },
            { result: "approved", latency_sec: 17 }
          ]
        )
      ).first

      expect(decision.latency_sec).to eq(28)
    end

    it "rejects out-of-order online operations" do
      operations = [
        build_operation(operation_id: "later", created_at: "2026-07-30T09:06:00+03:00"),
        build_operation(operation_id: "earlier", created_at: "2026-07-30T09:05:00+03:00")
      ]

      expect do
        described_class.call(
          operations: operations,
          providers: two_primary_pool,
          policy: build_policy,
          simulator: sequenced_simulator(%w[approved approved])
        )
      end.to raise_error(Routing::InvalidInputError, "operations must be ordered by created_at")
    end

    it "rejects a duplicate operation in the online stream" do
      operation = build_operation
      engine = described_class.new(
        [],
        two_primary_pool,
        build_policy,
        sequenced_simulator(%w[approved approved])
      )
      engine.route_one(operation)

      expect { engine.route_one(operation) }.to raise_error(
        Routing::InvalidInputError,
        "duplicate operation_id op_test"
      )
    end

    it "releases a reservation when the provider client raises", :aggregate_failures do
      providers = two_primary_pool
      simulator = Object.new
      simulator.define_singleton_method(:call) { |_provider| raise IOError, "provider unavailable" }

      expect do
        described_class.call(
          operations: [build_operation],
          providers: providers,
          policy: build_policy,
          simulator: simulator
        )
      end.to raise_error(IOError, "provider unavailable")
      expect(providers.fetch("vipay")).to have_attributes(in_progress_count: 0, daily_reserved_amount: 0)
    end

    it "sends a stable attempt idempotency key to keyword-aware provider clients" do
      received = []
      simulator = Object.new
      simulator.define_singleton_method(:call) do |provider, operation:, idempotency_key:|
        received << [provider.name, operation.id, idempotency_key]
        { result: "approved", latency_sec: 1 }
      end

      described_class.call(
        operations: [build_operation],
        providers: two_primary_pool,
        policy: build_policy,
        simulator: simulator
      )

      expect(received).to eq([["vipay", "op_test", "op_test:vipay"]])
    end

    it "never claims an ineligible fallback was selected" do
      providers = Routing::ProviderPool.new(
        [
          build_provider(status: "disabled"),
          fallback_provider(status: "disabled")
        ]
      )

      expect do
        described_class.call(
          operations: [build_operation],
          providers: providers,
          policy: build_policy,
          simulator: sequenced_simulator(%w[approved])
        )
      end.to raise_error(
        Routing::InvalidInputError,
        "operation op_test cannot be routed without violating hard constraints"
      )
    end

    def cascade_decision
      described_class.call(
        operations: [build_operation],
        providers: two_primary_pool,
        policy: build_policy,
        simulator: sequenced_simulator(%w[rejected approved])
      ).first
    end

    def rejected_fallback_decisions
      described_class.call(
        operations: traffic_share_operations,
        providers: traffic_share_pool,
        policy: build_policy("count_share" => { "enabled" => true, "weight" => 1.0 }),
        simulator: sequenced_simulator(%w[rejected approved approved])
      )
    end

    def traffic_share_operations
      [
        build_operation(operation_id: "fallback", amount: 200_000),
        build_operation(operation_id: "primary_1"),
        build_operation(operation_id: "primary_2")
      ]
    end

    def traffic_share_pool
      Routing::ProviderPool.new(
        [
          build_provider(traffic_percentage: 80),
          build_provider(payment_system: "payflow", traffic_percentage: 20, priority: 2),
          fallback_provider
        ]
      )
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

    def fallback_provider(**overrides)
      build_provider(payment_system: "spacepayments", traffic_percentage: 0, limit_amount_min: nil,
                     limit_amount_max: nil, daily_amount_limit: nil, in_progress_count_limit: nil,
                     in_progress_amount_limit: nil, banks: [], conversion_24h: 1.0, **overrides)
    end

    def sequenced_simulator(results)
      queue = results.dup
      simulator = Object.new
      simulator.define_singleton_method(:call) do |_provider|
        { result: queue.shift || "approved", latency_sec: 30 }
      end
      simulator
    end

    def outcome_simulator(outcomes)
      queue = outcomes.dup
      simulator = Object.new
      simulator.define_singleton_method(:call) { |_provider| queue.shift }
      simulator
    end

    def status_client(call_results:, status_results:)
      calls = call_results.dup
      statuses = status_results.dup
      client = Object.new
      client.define_singleton_method(:status_requests) { @status_requests ||= [] }
      client.define_singleton_method(:call) do |_provider, **|
        { result: calls.shift || "approved", latency_sec: 0 }
      end
      client.define_singleton_method(:status) do |_provider, operation_id:, idempotency_key:|
        status_requests << [operation_id, idempotency_key]
        { result: statuses.shift || "pending" }
      end
      client
    end

    def status_check_config
      {
        "enabled" => true,
        "initial_delay_sec" => 5,
        "retry_delays_sec" => [10],
        "max_attempts" => 3
      }
    end
  end
end
