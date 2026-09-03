# frozen_string_literal: true

RSpec.describe Routing::HardConstraints::Filter do
  subject(:evaluation) do
    described_class.call(operation: operation, providers: providers)
  end

  let(:operation) { build_operation }
  let(:vipay) { build_provider }
  let(:payflow) { build_provider(payment_system: "payflow", traffic_percentage: 35, banks: %w[sberbank alfa]) }
  let(:spacepayments) { fallback_provider }
  let(:providers) { [vipay, payflow, spacepayments] }

  it "returns primary providers that pass every check" do
    expect(evaluation.eligible.map(&:name)).to eq(%w[vipay payflow])
  end

  it "keeps spacepayments as fallback when it passes checks" do
    expect(evaluation.fallback).to eq(spacepayments)
  end

  it "records skip attempts for ineligible primaries" do
    result = described_class.call(operation: build_operation(bank: "alfa"), providers: providers)
    expect(result.skipped.first).to have_attributes(provider: "vipay", decision: "skipped", reason: "bank_not_in_list")
  end

  it "does not treat zero-traffic non-fallback providers as primaries" do
    ghost = build_provider(payment_system: "ghostpay", traffic_percentage: 0)
    result = described_class.call(operation: operation, providers: [ghost, spacepayments])
    expect(result).to have_attributes(eligible: [], skipped: [], fallback: spacepayments)
  end

  it "leaves fallback nil when spacepayments fails a hard check" do
    down = build_provider(payment_system: "spacepayments", traffic_percentage: 0, status: "disabled", banks: [])
    expect(described_class.call(operation: operation, providers: [vipay, down]).fallback).to be_nil
  end

  it "records the first failing check in table order" do
    blocked = build_provider(status: "disabled", limit_amount_max: 1)
    expect(described_class.call(operation: operation, providers: [blocked]).skipped.first.reason)
      .to eq("provider_inactive")
  end

  def fallback_provider
    build_provider(payment_system: "spacepayments", traffic_percentage: 0, limit_amount_min: nil,
                   limit_amount_max: nil, daily_amount_limit: nil, in_progress_count_limit: nil,
                   in_progress_amount_limit: nil, banks: [])
  end
end
