# frozen_string_literal: true

require "tmpdir"

RSpec.describe Routing::Concurrency::PersistQueue do
  it "flushes a debounced runtime snapshot on shutdown", :aggregate_failures do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "runtime.json")
      store = Routing::RuntimeStore.new(path)
      pool = Routing::ProviderPool.new([build_provider])
      state = Routing::RuntimeState.new(pool)
      checker = Routing::StatusChecker.new(
        state: state, providers: pool, client: Object.new,
        config: {
          "enabled" => false, "initial_delay_sec" => 5,
          "retry_delays_sec" => [5], "max_attempts" => 1
        }
      )
      queue = described_class.new(store: store, debounce_ms: 1, event_log: true)

      queue.enqueue(state: state, status_checker: checker)
      queue.shutdown

      expect(Routing::JsonFile.read(path)).to include("runtime_state")
      expect(File.exist?("#{path}.jsonl")).to be(true)
    end
  end
end
