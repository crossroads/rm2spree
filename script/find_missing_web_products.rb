#!/usr/bin/env ruby

puts "Finding products without translations..."

require File.join(File.dirname(__FILE__), '..', "lib", "odbc_spree.rb")
include Spree::ODBC

@rm = RM.new("live")
sheet_products = @rm.valid_products.map(&:upcase)
@rm.connect

@no_translations = []

@stock_records_current = @rm.fetch_stock_records

@stock_records_current.each do |stock_id, record|
  if record["custom1"].downcase.strip == "yes"
      @no_translations << record["Barcode"] unless sheet_products.include?(record["Barcode"].upcase)
  end
end

@rm.log.debug(%Q"

::  MYOB products marked for webstore, but without translations in spreadsheet:
     - Total:  #{@no_translations.size}
")
@rm.log.debug " -------- "
@rm.log.debug @no_translations.sort.collect{|x| "'#{x}'"}.join(", ")

