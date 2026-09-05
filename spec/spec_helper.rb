# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "routing"

SPEC_ROOT = File.expand_path("..", __dir__)

Dir.glob("**/*.rb", base: File.expand_path("support", __dir__)).sort.each do |relative|
  require File.expand_path(relative, File.expand_path("support", __dir__))
end

RSpec.configure do |config|
  config.include RoutingSpec::Fixtures
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
