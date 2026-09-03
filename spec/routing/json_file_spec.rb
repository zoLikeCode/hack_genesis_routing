# frozen_string_literal: true

RSpec.describe Routing::JsonFile do
  describe ".read" do
    it "parses JSON from disk" do
      path = File.join(SPEC_ROOT, "data/providers.json")
      expect(described_class.read(path)).to include("providers")
    end

    it "raises InvalidInputError when the file is missing" do
      expect { described_class.read("missing.json") }.to raise_error(Routing::InvalidInputError)
    end

    it "raises InvalidInputError when JSON is invalid" do
      path = File.join(SPEC_ROOT, "spec/support/fixtures.rb")
      expect { described_class.read(path) }.to raise_error(Routing::InvalidInputError)
    end
  end
end
