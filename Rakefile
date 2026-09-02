require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "spec/**/*_spec.rb"
end

desc "Run the Rails integration suite (loads Rails from dev deps only)"
RSpec::Core::RakeTask.new("spec:rails") do |t|
  t.pattern = "spec-rails/**/*_spec.rb"
  t.rspec_opts = "-I spec-rails --require rails_helper"
end

task default: %i[spec spec:rails standard]
