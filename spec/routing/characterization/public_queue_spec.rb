# frozen_string_literal: true

RSpec.describe "seed-1 public-queue characterization" do
  it "matches frozen sequential Decision hashes" do
    expect(actual_decisions).to eq(expected_decisions)
  end

  def actual_decisions
    policy = Routing::Policy.load(File.join(SPEC_ROOT, "config/routing_policy.yml"))
    providers = Routing::ProviderPool.load(File.join(SPEC_ROOT, "data/providers.json"))
    operations = Routing::Operation.load_queue(File.join(SPEC_ROOT, "data/operations_queue_10.json"))
    history = Routing::History.load(File.join(SPEC_ROOT, "data/operations_history.csv"))
    state = Routing::RuntimeState.new(
      providers, history: history, metrics_config: policy.metrics, policy: policy
    )
    Routing::Engine.call(
      operations: operations, providers: providers, policy: policy, state: state, concurrent: false
    ).map(&:to_h)
  end

  def expected_decisions
    Routing::JsonFile.read(File.join(SPEC_ROOT, "spec/data/public_queue_decisions.json"))
  end
end
