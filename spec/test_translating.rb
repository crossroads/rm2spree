#!/usr/bin/env ruby

require File.join(File.dirname(__FILE__), "..", "lib", "odbc_spree")

include Spree::ODBC
# ------ Begin Code Execution -------

@rm = RM.new("preview", false)

ProductSync.find("translate")

