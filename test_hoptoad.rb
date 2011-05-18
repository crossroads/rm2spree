#!/usr/bin/env ruby
require File.join(File.dirname(__FILE__), "lib", "odbc_spree")
include Spree::ODBC

env = ARGV[0]
if not ["test", "local", "preview", "beta", "live"].include? env
  puts "Wrong environment argument. Should be 'test', 'local', 'preview', 'beta', or 'live'."
  exit
end

@rm = RM.new(env)
@rm.send_hoptoad_notification("This is a test error.")

