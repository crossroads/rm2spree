require File.join("..", "lib", "odbc_spree.rb")

@rm = RM.new("preview")

@no_image = []
@no_weight = []

@stock_records_current = @rm.fetch_stock_records

@stock_records_current.each do |stock_id, record|
  if record["custom1"].downcase == "yes"
      @no_image << record["Barcode"] unless find_image(record["Barcode"])
      @no_weight << record["Barcode"] unless (record["custom2"].to_f > 0 and record["custom2"].to_f < 10)
  end
end

@rm.log.debug(%Q"

:: Invalid web store products:
     - No image count:  #{@no_image.size}
     - No weight count: #{@no_weight.size}
     - Total: #{@no_image.size + @no_weight.size}
")

@rm.log.debug " ---- barcodes without images ---- "
@rm.log.debug @no_image.sort.collect{|x| "'#{x}'"}.join(", ")

@rm.log.debug "\n\n\n ---- barcodes without weights ---- "
@rm.log.debug @no_weight.sort.collect{|x| "'#{x}'"}.join(", ")

