#!/usr/bin/env ruby
require File.join(File.dirname(__FILE__), "lib", "odbc_spree")
include Spree::ODBC

env = ARGV[0]
if not ["test", "local", "preview", "beta", "live"].include? env
  puts "Wrong environment argument. Should be 'test', 'local', 'preview', 'beta', or 'live'."
  exit
end

config = YAML.load_file(File.join("config", "config_#{env}.yml"))

Toadhopper.new(config["hoptoad_api_key"], :notify_host => (config["hoptoad_host"])).deploy!

