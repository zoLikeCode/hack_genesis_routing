# frozen_string_literal: true

RSpec.describe Routing::RuntimeState do
  subject(:state) { described_class.new(pool) }

  let(:provider) { build_provider }
  let(:pool) { Routing::ProviderPool.new([provider]) }
  let(:operation) { build_operation }

  it "continues admission sequence after seeded history" do
    observation = build_observation(admission_sequence: 7)
    history = Routing::History.new({ "vipay" => {} }, observations: [observation])
    provider = build_provider
    state = described_class.new(Routing::ProviderPool.new([provider]), history: history)
    operation = build_operation
    reservation = state.try_reserve!(provider, operation, expected_revision: 0).reservation

    state.mark_dispatching!(reservation, at: operation.created_at)

    expect(reservation.admission_sequence).to eq(8)
  end

  it "returns a point-in-time provider copy", :aggregate_failures do
    snapshot = state.snapshot
    pool.reserve!(provider, operation)

    expect(snapshot.providers.first.in_progress_count).to eq(0)
    expect(pool.fetch("vipay").in_progress_count).to eq(1)
  end

  it "returns a readonly soft-goal snapshot" do
    snapshot = state.snapshot.soft_goals

    expect { snapshot.record_selection!("vipay") }.to raise_error(
      Routing::InvariantError,
      "cannot mutate a readonly snapshot"
    )
  end

  it "rejects a reservation calculated from a stale revision", :aggregate_failures do
    revision = state.snapshot.revision
    first = state.try_reserve!(provider, operation, expected_revision: revision)
    second = state.try_reserve!(provider, build_operation(operation_id: "op_2"), expected_revision: revision)

    expect(first).to be_reserved
    expect(second).to be_stale
  end

  it "makes a pending reservation visible to the next snapshot", :aggregate_failures do
    reservation = reserve
    snapshot = state.snapshot
    current = snapshot.providers.first

    expect(reservation.status).to eq("reserved")
    expect(snapshot.soft_goals.count("vipay")).to eq(1)
    expect(snapshot.soft_goals.volume("vipay")).to eq(15_000)
    expect(current).to have_attributes(in_progress_count: 1, daily_reserved_amount: 15_000)
  end

  it "commits an approved reservation without double-counting its volume", :aggregate_failures do
    reservation = dispatch
    state.approve!(reservation)
    snapshot = state.snapshot

    expect(reservation.status).to eq("approved")
    expect(snapshot.soft_goals.count("vipay")).to eq(1)
    expect(snapshot.soft_goals.volume("vipay")).to eq(15_000)
    expect(snapshot.providers.first).to have_attributes(in_progress_count: 0, daily_reserved_amount: 0)
  end

  it "rolls back every provisional coefficient after rejection", :aggregate_failures do
    reservation = dispatch
    state.reject!(reservation)
    snapshot = state.snapshot

    expect(reservation.status).to eq("rejected")
    expect(snapshot.soft_goals.count("vipay")).to eq(0)
    expect(snapshot.soft_goals.volume("vipay")).to eq(0)
    expect(snapshot.providers.first).to have_attributes(in_progress_count: 0, daily_approved_amount: 0)
  end

  it "keeps timeout capacity until a late cancellation compensates current state", :aggregate_failures do
    reservation = dispatch
    state.mark_timeout!(reservation)

    expect(state.snapshot.soft_goals.count("vipay")).to eq(1)

    state.resolve_timeout!(operation_id: operation.id, provider_name: provider.name, result: "cancelled")

    expect(state.snapshot.soft_goals.count("vipay")).to eq(0)
    expect(pool.fetch("vipay")).to have_attributes(in_progress_count: 0, daily_approved_amount: 0)
  end

  it "commits a late timeout approval exactly once", :aggregate_failures do
    reservation = dispatch
    state.mark_timeout!(reservation)
    resolve_timeout("approved")

    expect(reservation.status).to eq("approved")
    expect(state.snapshot.soft_goals.count("vipay")).to eq(1)
    expect(pool.fetch("vipay")).to have_attributes(
      in_progress_count: 0,
      daily_reserved_amount: 0,
      daily_approved_amount: 15_000
    )
    repeated = resolve_timeout("approved")
    conflicting = resolve_timeout("cancelled")

    expect(repeated).to equal(reservation)
    expect(conflicting).to equal(reservation)
    expect(pool.fetch("vipay").daily_approved_amount).to eq(15_000)
  end

  it "records attempt outcomes into the provider window" do
    state.record_metric!(operation: operation, provider_name: "vipay", status: "rejected", latency_sec: 9)

    expect(state.metrics.observations_for("vipay").map(&:status)).to eq(%w[rejected])
  end

  it "rewrites a timed-out metric after status-check settlement", :aggregate_failures do
    reservation = dispatch
    state.mark_timeout!(reservation)
    state.record_metric!(operation: operation, provider_name: "vipay", status: "expired", latency_sec: 40)
    state.resolve_timeout!(operation_id: operation.id, provider_name: provider.name, result: "approved")

    row = state.metrics.observations_for("vipay").first
    expect(row).to have_attributes(initial_status: "expired", status: "approved", latency_sec: 40)
  end

  it "keeps an unknown observed latency as nil" do
    state.record_metric!(operation: operation, provider_name: "vipay", status: "rejected", latency_sec: nil)

    expect(state.metrics.observations_for("vipay").first.latency_sec).to be_nil
  end

  it "records and settles a normal provider outcome atomically", :aggregate_failures do
    reservation = dispatch
    state.record_outcome!(
      reservation: reservation, operation: operation, status: "approved", latency_sec: 12
    )

    expect(reservation.status).to eq("approved")
    expect(state.metrics.observations_for("vipay").first).to have_attributes(
      initial_status: "approved", status: "approved", latency_sec: 12
    )
  end

  it "rechecks hard constraints inside the reservation boundary", :aggregate_failures do
    blocked = build_provider(status: "disabled")
    blocked_state = described_class.new(Routing::ProviderPool.new([blocked]))
    result = blocked_state.try_reserve!(blocked, operation, expected_revision: 0)

    expect(result).not_to be_reserved
    expect(result.reason).to eq("provider_inactive")
  end

  it "does not charge RPM for a reserved payout that never dispatched", :aggregate_failures do
    reservation = reserve
    at = operation.created_at
    expect(provider.request_count_at(at)).to eq(0)

    state.drop_reservation!(reservation)

    expect(provider.request_count_at(at)).to eq(0)
    expect(reservation.status).to eq("rejected")
    expect(provider.in_progress_count).to eq(0)
  end

  def reserve
    state.try_reserve!(provider, operation, expected_revision: state.snapshot.revision).reservation
  end

  def dispatch
    reservation = reserve
    state.mark_dispatching!(reservation, at: operation.created_at)
    reservation
  end

  def resolve_timeout(result)
    state.resolve_timeout!(operation_id: operation.id, provider_name: provider.name, result: result)
  end
end
