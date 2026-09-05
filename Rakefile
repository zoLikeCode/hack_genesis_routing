# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new do |task|
  task.patterns = FileList["lib/**/*.rb", "spec/**/*.rb", "bin/*", "Rakefile"].to_a
end

desc "Validate routing decisions against the public 10-op queue (default: data/sample_routing_decisions.json)"
task :validate, [:decisions] do |_t, args|
  decisions = args[:decisions] || "data/sample_routing_decisions.json"
  sh RbConfig.ruby, "scripts/validate_10.rb", decisions
end

task default: %i[spec rubocop]
