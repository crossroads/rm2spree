require "odbc_spree_functions"

Start_Time = Time.now
$LOG = Logger.new("odbc_export.log", 10, 1024000)
$LOG.formatter = Logger::Formatter.new
$LOG.formatter.datetime_format = "%Y-%m-%d %H:%M:%S"
$LOG.debug_x("\n\n -=- MYOB Database Synchronization Script started. -=- \n")

# ------ Begin Code Execution -------

@no_image = []
@no_weight = []

@stock_records_current = fetch_stock_records

@stock_records_current.each do |stock_id, record|
  if record["custom1"].downcase == "yes" 
      @no_image << record["Barcode"] unless find_image(record["Barcode"])
      @no_weight << record["Barcode"] unless (record["custom2"].to_f > 0 and record["custom2"].to_f < 10)
  end
end

$LOG.debug_x(%Q"

:: Invalid web store products:
     - No image count:  #{@no_image.size}    
     - No weight count: #{@no_weight.size}  
     - Total: #{@no_image.size + @no_weight.size}    
")

$LOG.debug_x " ---- barcodes without images ---- "
$LOG.debug_x @no_image.sort.collect{|x| "'#{x}'"}.join(", ")

$LOG.debug_x "\n\n\n ---- barcodes without weights ---- "
$LOG.debug_x @no_weight.sort.collect{|x| "'#{x}'"}.join(", ")