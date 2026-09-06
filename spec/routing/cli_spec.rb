# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe Routing::CLI do
  it "returns 0 for the public queue" do
    with_cli_output { |decisions, report| expect(run_cli(decisions, report)).to eq(0) }
  end

  it "writes a report file" do
    with_cli_output do |decisions, report|
      run_cli(decisions, report)
      expect(File.exist?(report)).to be(true)
    end
  end

  it "writes an operational runtime snapshot" do
    with_cli_output do |decisions, report|
      run_cli(decisions, report)
      runtime = "#{report}.runtime.json"
      expect(Routing::JsonFile.read(runtime)).to include(
        "runtime_state", "status_checks", "circuit_breakers"
      )
    end
  end

  it "writes decisions that pass the public validator" do
    with_cli_output do |decisions, report|
      run_cli(decisions, report)
      expect(validate(decisions)).to be_success
    end
  end

  it "returns 1 when input files are missing" do
    expect(described_class.start(["--providers", "missing-providers.json"])).to eq(1)
  end

  def with_cli_output
    Dir.mktmpdir do |dir|
      yield File.join(dir, "routing_decisions_test.json"), File.join(dir, "routing_report_test.json")
    end
  end

  def run_cli(decisions, report)
    described_class.start(
      [
        "--providers", File.join(SPEC_ROOT, "data/providers.json"),
        "--queue", File.join(SPEC_ROOT, "data/operations_queue_10.json"),
        "--policy", File.join(SPEC_ROOT, "config/routing_policy.yml"),
        "--history", File.join(SPEC_ROOT, "data/operations_history.csv"),
        "--decisions", decisions,
        "--report", report,
        "--runtime", "#{report}.runtime.json"
      ]
    )
  end

  def validate(decisions)
    _stdout, status = Open3.capture2(RbConfig.ruby, File.join(SPEC_ROOT, "scripts/validate_10.rb"), decisions)
    status
  end
end
