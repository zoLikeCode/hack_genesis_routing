# frozen_string_literal: true

require "tmpdir"

RSpec.describe Routing::RuntimeStore do
  it "atomically persists reservations, checks, metrics and circuit state", :aggregate_failures do
    Dir.mktmpdir do |dir|
      state, checker = timed_out_runtime
      path = File.join(dir, "runtime.json")

      described_class.new(path).save(state: state, status_checker: checker)
      stored = Routing::JsonFile.read(path)

      expect(stored.dig("runtime_state", "reservations", 0)).to include(
        "idempotency_key" => "op_test:vipay", "status" => "timed_out"
      )
      expect(stored.dig("status_checks", "scheduled")).to eq(1)
      expect(stored.dig("runtime_state", "metrics", "vipay", 0, "initial_status")).to eq("expired")
    end
  end

  def timed_out_runtime
    provider = build_provider
    providers = Routing::ProviderPool.new([provider])
    state = Routing::RuntimeState.new(providers)
    operation = build_operation
    reservation = state.try_reserve!(provider, operation, expected_revision: 0).reservation
    state.mark_dispatching!(reservation, at: operation.created_at)
    state.record_outcome!(reservation: reservation, operation: operation, status: "expired", latency_sec: 5)
    checker = build_checker(state, providers)
    checker.schedule(reservation, timed_out_at: operation.created_at)
    [state, checker]
  end

  def build_checker(state, providers)
    Routing::StatusChecker.new(
      state: state, providers: providers, client: Object.new,
      config: {
        "enabled" => true, "initial_delay_sec" => 5,
        "retry_delays_sec" => [5], "max_attempts" => 1
      }
    )
  end
end
