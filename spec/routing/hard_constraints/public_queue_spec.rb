# frozen_string_literal: true

RSpec.describe Routing::HardConstraints::Filter do
  describe ".call" do
    let(:pool) { Routing::ProviderPool.load(File.join(SPEC_ROOT, "data/providers.json")) }
    let(:queue) { Routing::Operation.load_queue(File.join(SPEC_ROOT, "data/operations_queue_10.json")) }
    let(:reference) { Routing::JsonFile.read(File.join(SPEC_ROOT, "data/reference_decisions.json")) }
    let(:evaluations) do
      queue.to_h { |operation| [operation.id, described_class.call(operation: operation, providers: pool)] }
    end

    it "matches eligible primaries for every public operation" do
      actual = evaluations.transform_values { |evaluation| evaluation.eligible.map(&:name) }
      expect(actual).to eq(reference.fetch("eligible_providers"))
    end

    it "matches expected skip reasons for every public operation" do
      actual = evaluations.transform_values { |evaluation| skip_reasons(evaluation) }
      expect(actual).to include(reference.fetch("skip_reasons_expected"))
    end

    it "keeps spacepayments as fallback on the public snapshot" do
      names = evaluations.each_value.map { |evaluation| evaluation.fallback&.name }.uniq
      expect(names).to eq(%w[spacepayments])
    end

    def skip_reasons(evaluation)
      evaluation.skipped.to_h { |attempt| [attempt.provider, attempt.reason] }
    end
  end
end
