# frozen_string_literal: true

RSpec.describe Routing do
  describe ".assert" do
    it "returns nil when the condition holds" do
      expect(described_class.assert(true, "ok")).to be_nil
    end

    it "raises InvariantError when the condition fails" do
      expect { described_class.assert(false, "broken") }.to raise_error(Routing::InvariantError, "broken")
    end
  end
end
