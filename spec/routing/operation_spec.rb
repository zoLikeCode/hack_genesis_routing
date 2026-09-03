# frozen_string_literal: true

RSpec.describe Routing::Operation do
  describe ".new" do
    it "loads required fields" do
      expect(build_operation(operation_id: "op_101")).to have_attributes(
        id: "op_101", amount: 15_000, bank: "sberbank"
      )
    end

    it "parses created_at as Time" do
      expect(build_operation.created_at).to eq(Time.iso8601("2026-07-30T09:05:00+03:00"))
    end

    it "rejects a missing operation_id" do
      expect { described_class.new("amount" => 1) }.to raise_error(Routing::InvariantError)
    end

    it "rejects a negative amount" do
      expect { described_class.new("operation_id" => "op_x", "amount" => -1) }
        .to raise_error(Routing::InvariantError)
    end

    it "rejects an invalid created_at" do
      expect { described_class.new("operation_id" => "op_x", "amount" => 1, "created_at" => "not-a-time") }
        .to raise_error(Routing::InvalidInputError)
    end
  end
end
