# frozen_string_literal: true

RSpec.describe Routing::CircuitBreaker do
  it "opens when the unresolved count threshold is reached", :aggregate_failures do
    breaker = described_class.new(
      "enabled" => true,
      "unresolved_count_limit" => 2,
      "unresolved_amount_limit" => 1_000_000
    )
    first = Routing::Reservation.new(operation: build_operation(operation_id: "first"), provider_name: "vipay")
    second = Routing::Reservation.new(operation: build_operation(operation_id: "second"), provider_name: "vipay")

    breaker.record_unresolved!(first)
    expect(breaker).not_to be_open("vipay")
    breaker.record_unresolved!(second)

    expect(breaker).to be_open("vipay")
    expect(breaker.summary.fetch("vipay")).to include(
      "status" => "open", "unresolved_count" => 2, "unresolved_amount" => 30_000
    )
  end

  it "opens when the unresolved amount threshold is reached" do
    breaker = described_class.new(
      "enabled" => true,
      "unresolved_count_limit" => 10,
      "unresolved_amount_limit" => 10_000
    )
    reservation = Routing::Reservation.new(operation: build_operation, provider_name: "vipay")

    breaker.record_unresolved!(reservation)

    expect(breaker.open_provider_names).to eq(["vipay"])
  end
end
