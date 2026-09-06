# frozen_string_literal: true

RSpec.describe Routing::Settlement do
  it "releases a definite miss without recording an attempted payout", :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    provider = build_provider
    pool = Routing::ProviderPool.new([provider, fallback])
    state = Routing::RuntimeState.new(pool)
    operation = build_operation
    reservation = state.try_reserve!(provider, operation, expected_revision: 0).reservation
    context = Routing::RouteContext.new
    settlement = described_class.new(
      state: state,
      policy: build_policy,
      status_check_runner: status_runner(state, pool),
      persist: -> {}
    )
    selection = instance_double(Routing::Router::Selection, provider: provider, fallback?: false)
    error = Routing::AdapterError.from(IOError.new("reset"), reservation: reservation)

    result = settlement.apply_failure(
      operation: operation, selection: selection, context: context,
      reservation: reservation, error: error, timeout_at: operation.created_at
    )

    expect(result).to be_nil
    expect(context.attempted).to eq([])
    expect(context.temporarily_excluded).to eq(["vipay"])
    expect(provider).to have_attributes(in_progress_count: 0)
    expect(provider.request_count_at(operation.created_at)).to eq(0)
  end

  def fallback
    build_provider(payment_system: "spacepayments", traffic_percentage: 0)
  end

  def status_runner(state, pool)
    checker = Routing::StatusChecker.new(
      state: state, providers: pool, client: Object.new,
      config: {
        "enabled" => true, "initial_delay_sec" => 5,
        "retry_delays_sec" => [5], "max_attempts" => 1
      }
    )
    Routing::StatusCheckRunner.new(checker: checker)
  end
end
