# frozen_string_literal: true

require "optparse"

module Routing
  class CLI
    def self.start(argv)
      new.start(argv)
    end

    def start(argv)
      options = parse(argv)
      warn "Routing engine is not implemented yet (#{options.inspect})"
      0
    end

    private

    def default_options
      {
        providers: nil,
        queue: nil,
        history: nil,
        policy: File.expand_path("../../config/routing_policy.yml", __dir__),
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
      opts.on("--providers PATH", "providers.json") { |v| options[:providers] = v }
      opts.on("--queue PATH", "operations_queue.json") { |v| options[:queue] = v }
      opts.on("--history PATH", "operations_history.csv") { |v| options[:history] = v }
      opts.on("--policy PATH", "routing policy YAML") { |v| options[:policy] = v }
      opts.on("--decisions PATH", "output routing_decisions JSON") { |v| options[:decisions_out] = v }
      opts.on("--report PATH", "output routing_report JSON") { |v| options[:report_out] = v }
      opts.on("-h", "--help", "Show help") do
        puts opts
        exit 0
      end
    end
  end
end
