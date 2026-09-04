# frozen_string_literal: true

require "optparse"

module Routing
  class CLI
    ROOT = File.expand_path("../..", __dir__)

    def self.start(argv)
      new.start(argv)
    end

    def start(argv)
      run(parse(argv))
    rescue InvalidInputError, InvariantError, OptionParser::ParseError => e
      warn e.message
      1
    end

    private

    def default_options
      {
        providers: File.join(ROOT, "data/providers.json"),
        queue: File.join(ROOT, "data/operations_queue_10.json"),
        history: File.join(ROOT, "data/operations_history.csv"),
        policy: File.join(ROOT, "config/routing_policy.yml"),
        decisions_out: "routing_decisions_test.json",
        report_out: "routing_report_test.json"
      }
    end

    def parse(argv)
      options = default_options
      OptionParser.new { |opts| define_options(opts, options) }.parse!(argv)
      options
    end

    def define_options(opts, options)
      opts.banner = "Usage: bin/route [options]"
      opts.on("--providers PATH", "providers.json") { |value| options[:providers] = value }
      opts.on("--queue PATH", "operations_queue.json") { |value| options[:queue] = value }
      opts.on("--history PATH", "operations_history.csv") { |value| options[:history] = value }
      opts.on("--policy PATH", "routing policy YAML") { |value| options[:policy] = value }
      opts.on("--decisions PATH", "output routing_decisions JSON") { |value| options[:decisions_out] = value }
      opts.on("--report PATH", "output routing_report JSON") { |value| options[:report_out] = value }
      opts.on("-h", "--help", "Show help") do
        puts opts
        exit 0
      end
    end

    def run(options)
      policy = Policy.load(options[:policy])
      providers = ProviderPool.load(options[:providers])
      operations = Operation.load_queue(options[:queue])
      history = History.load(options[:history]) if options[:history] && File.exist?(options[:history])
      state = RuntimeState.new(providers, history: history, metrics_config: policy.metrics)
      engine = Engine.new(operations, providers, policy, state: state)
      decisions = engine.call
      report = Report.call(
        decisions: decisions,
        operations: operations,
        providers: providers,
        policy: policy,
        history: history,
        runtime_state: engine.state,
        status_checker: engine.status_checker
      )
      JsonFile.write(options[:decisions_out], decisions.map(&:to_h))
      JsonFile.write(options[:report_out], report)
      0
    end
  end
end
