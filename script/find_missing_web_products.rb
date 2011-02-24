#!/usr/bin/env ruby

puts "Finding products without translations..."

require File.join(File.dirname(__FILE__), '..', "lib", "odbc_spree.rb")
include Spree::ODBC

sheet = ProductSpreadsheet.new
sheet_products = sheet.valid_products.map(&:upcase)

@rm = RM.new("preview")
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

