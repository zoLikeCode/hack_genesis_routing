# frozen_string_literal: true

RSpec.describe Routing::Replay do
  it "groups simultaneous arrivals and preserves short gaps while capping long gaps" do
    replay = described_class.new(operations_at(0, 0, 1, 300, 300, 305))

    expect(replay.groups.map { |offset, group| [offset, group.size] }).to eq(
      [[0, 2], [1, 1], [31, 2], [36, 1]]
    )
  end

  it "rejects missing timestamps" do
    expect { described_class.new([build_operation(created_at: nil)]) }.to raise_error(Routing::InvalidInputError)
  end

  it "rejects backwards timestamps" do
    expect { described_class.new(operations_at(2, 1)) }.to raise_error(Routing::InvalidInputError)
  end

  it "enforces RPM across a burst without serializing arrivals", :aggregate_failures do
    decisions = replay_decisions(operations_at(0, 0, 1), requests_per_minute_limit: 2)

    expect(decisions.map(&:selected_provider)).to eq(%w[vipay vipay spacepayments])
    expect(decisions.last.attempts.map(&:reason)).to include("rate_limit_exceeded")
  end

  it "keeps a payout in flight when another operation arrives", :aggregate_failures do
    decisions = replay_decisions(operations_at(0, 1), in_progress_count_limit: 1, avg_latency_sec: 10)

    expect(decisions.map(&:selected_provider)).to eq(%w[vipay spacepayments])
    expect(decisions).to all(be_final)
  end

  it "expires RPM usage after the model window passes" do
    decisions = replay_decisions(operations_at(0, 30, 60, 90), requests_per_minute_limit: 2)

    expect(decisions.last.selected_provider).to eq("vipay")
  end

  def operations_at(*offsets)
    start = Time.iso8601("2026-07-30T09:00:00+03:00")
    offsets.each_with_index.map do |offset, index|
      build_operation(operation_id: "replay_#{index}", created_at: start + offset)
    end
  end

  def replay_decisions(operations, **limits)
    primary = build_provider(conversion_24h: 1.0, avg_latency_sec: 0, **limits)
    fallback = build_provider(payment_system: "spacepayments", conversion_24h: 1.0, avg_latency_sec: 0)
    Routing::Engine.call(
      operations: operations, providers: Routing::ProviderPool.new([primary, fallback]),
      policy: build_policy, concurrent: true, replay: true
    )
  end
end
