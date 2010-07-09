require "odbc_spree_functions.rb"

Start_Time = Time.now
$LOG = Logger.new("test_products_odbc_export.log", 10, 1024000)
$LOG.formatter = Logger::Formatter.new
$LOG.formatter.datetime_format = "%Y-%m-%d %H:%M:%S"
$LOG.debug_x("\n\n -=- MYOB Database Synchronization Script started. -=- \n")

# ------ Begin Code Execution -------

Taxon_Sync.find("translate") 