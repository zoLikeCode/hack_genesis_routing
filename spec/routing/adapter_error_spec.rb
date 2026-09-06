# frozen_string_literal: true

RSpec.describe Routing::AdapterError do
  it "classifies a dispatching reservation as ambiguous" do
    reservation = Routing::Reservation.new(operation: build_operation, provider_name: "vipay")
    reservation.mark_dispatching!(admission_sequence: 1)
    error = described_class.from(IOError.new("broken pipe"), reservation: reservation)

    expect(error).to be_ambiguous
  end

  it "classifies a reserved reservation as a definite miss" do
    reservation = Routing::Reservation.new(operation: build_operation, provider_name: "vipay")
    error = described_class.from(IOError.new("dns"), reservation: reservation)

    expect(error).to be_definite_miss
  end
end
