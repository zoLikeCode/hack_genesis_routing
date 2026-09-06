# frozen_string_literal: true

require "tmpdir"

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

  describe ".write" do
    it "writes pretty JSON that can be read back" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.json")
        described_class.write(path, { "ok" => true })
        expect(described_class.read(path)).to eq("ok" => true)
      end
    end

    it "replaces an existing JSON snapshot" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.json")
        described_class.write(path, { "revision" => 1 })

        described_class.write(path, { "revision" => 2 })

        expect(described_class.read(path)).to eq("revision" => 2)
      end
    end

    it "raises InvalidInputError when the parent directory is missing" do
      path = File.join("missing-json-parent-#{Process.pid}", "out.json")
      expect { described_class.write(path, {}) }.to raise_error(Routing::InvalidInputError)
    end
  end
end
