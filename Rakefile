require 'rubygems'
require "bundler/setup"

require 'rake'
require 'spec/rake/spectask'

begin
  namespace :bamboo do
    desc 'Run the specs for bamboo (requires ci_reporter)' 
    Spec::Rake::SpecTask.new(:spec) do |t|
      t.spec_opts = ["--require #{Gem.path.last}/gems/ci_reporter-1.6.2/lib/ci/reporter/rake/rspec_loader --format CI::Reporter::RSpec"]
      t.spec_files = FileList['spec/**/*_spec.rb']
    end
  end
rescue StandardError => e
  puts "Rake error: #{e}"
end
