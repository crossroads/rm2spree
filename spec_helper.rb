require 'mocha'

class Logger                    # Overwrite the logger class so that it only *displays* messages, and doesnt write them to log file.
  def info_x(message)
    puts message
  end
  def debug_x(message)
    #puts message
  end
  def error_x(message)
    puts message
  end
end

class Multipart                 # Overwrite the 'Multipart' code so that it doesnt actually post with net/http
  def post(to_url, content_type, user, password)
    return true
  end
end

class MockSMTP
  def enable_starttls
  end
  
  def start(helo, user, pass, login_type)
  end
end

class MockODBCConnection
  def select_all(sql_string)
    return sample_odbc_stock if sql_string=~ /\"Stock\"/
    return sample_odbc_categories if sql_string=~ /\"CategoryValues\"/
    return [["1.0", 1, 2, 2, 50]] if sql_string=~ /\"CategorisedStock\"/
    return sample_categorised_values if sql_string=~ /\"CategorisedValues\"/
    return sample_odbc_department_values if sql_string=~ /\"Departments\"/
  end
  
  def columns(table_name)
    sample_stock_fields
  end
  
  def disconnect
  end
end

def sample_categorised_values
  [[1, 2, 19], [3, 2, 19],[1, 2, 10], [3, 2, 10]]
end

def sample_odbc_categories
 [[10, 0, "DECOR"],
 [9, 0, "CHOC"],
 [8, 0, "CANDLE"],
 [7, 0, "WALLET"],
 [6, 0, "SCARF"],
 [5, 0, "KEY"],
 [4, 0, "HAT"],
 [3, 0, "HAIR"],
 [2, 0, "BELT"],
 [1, 0, "BAG"],
 [0, 0, "<N/A>"]]
end

def sample_categories
  {5=>"KEY",
  0=>"<N/A>",
  6=>"SCARF",
  1=>"BAG",
  7=>"WALLET",
  2=>"BELT",
  8=>"CANDLE",
  3=>"HAIR", 
  9=>"CHOC",
  4=>"HAT",
  10=>"DECOR"}
end

def sample_odbc_department_values
  [[5, 0, "GIFT SETS", "6/03/2008 22:56"],
  [4, 0, "FOOD", "7/03/2008 10:21"],
  [3, 0, "CLOTHING", "7/03/2008 10:19"],
  [2, 0, "CHRISTMAS", "7/03/2008 10:19"],
  [1, 0, "ACCESSORY", "9/11/2008 17:30"],
  [0, 0, "<Default>", "25/04/2008 16:44"]]
end

def sample_department_values
  {5=>"GIFT SETS",
  1=>"ACCESSORY",
  2=>"CHRISTMAS",
  3=>"CLOTHING",
  4=>"FOOD"}
end


def sample_odbc_stock
  [["1.0", 1, "SMBL6132", 0, "yes", "", "", "0", "0", "0", "0", "0", "0", "Bag - woven multi colour w/overlap",
  "multi colour w/overlap<br /><br />Want to know more about who made this item? Click <a href=\"http://globalhandicrafts.org/Producers/Bread_of_Life/\" target=\"_blank\"> here</a>.",
  "ACCESS", "BAG", "N-T", 38.2, "N-T", 75.0,
  "0.0", "0.0", "0.0", "Thu, 06 Mar 2008 22:56:09 +0000", "0", "0", "0", "0.0", "0.0", 9, "Tue, 16 Dec 2008 16:26:10 +0000",
  "0", "0.0", false, "0", "0", ""], 
  ["2.0", 1, "SMBL6134", 0, "yes", "", "", "0", "0", "0", "0", "0", "0", "Bag - woven multi colour", "Woven multi colour<br /><br />Want to know more about who made this item? Click <a href=\"http://globalhandicrafts.org/Producers/Bread_of_Life/\" target=\"_blank\"> here</a>.",
  "ACCESS", "BAG", "N-T", "65.4", "N-T", "130.0", "0.0", "0.0", "0.0", "Thu, 06 Mar 2008 22:56:09 +0000", "0",
  "0", 0.0, "0.0", "0.0", 9, "Tue, 16 Dec 2008 16:26:41 +0000", "0", "0.0", false, "0", "0", ""],
  ["3.0", 1, "SMBL6133", 0, "no", "", "", "0", "0", "0", "0", "0", "0", "Bag multi colour weaving no overlap",
  "multi colour without overlap<br /><br />Want to know more about who made this item? Click <a href=\"http://globalhandicrafts.org/Producers/Bread_of_Life/\" target=\"_blank\"> here</a>.",
  "ACCESS", "BAG", "N-T", 38.2, "N-T", 75.0, "0.0", "0.0", "0.0", "Thu, 06 Mar 2008 22:56:09 +0000", "0", "0",
  0.0, "0.0", "0.0", 9, "Tue, 16 Dec 2008 16:26:28 +0000", "0", "0.0", false, "0", "0", "3.JPG"]]
end

def sample_stock_fields
  fields_array = []
  ["stock_id", "dept_id", "Barcode", "PLU", "custom1", "custom2", "sales_prompt",
  "inactive", "allow_renaming", "allow_fractions", "package", "tax_components",
  "print_components", "description", "longdesc", "cat1", "cat2", "goods_tax", "cost",
  "sales_tax", "sell", "quantity", "layby_qty", "salesorder_qty", "date_created",
  "track_serial", "static_quantity", "bonus", "order_threshold", "order_quantity",
  "supplier_id", "date_modified", "freight", "tare_weight", "unitof_measure",
  "weighted", "external", "picture_file_name"].each do |key|
      fields_array << {:name => key}
  end  
  fields_array
end

def sample_spree_record
    {"permalink"=>"ruby-baseball-jersey",
    "name"=>"Rasha Bag - Mother of Africa",
    "tax_category_id"=>nil,
    "created_at"=>"Wed Oct 07 09:46:10 UTC 2009",
    "available_on"=>"Sat Oct 10 09:11:00 UTC 2009",
    "shipping_category_id"=>nil,
    "updated_at"=>"Tue Oct 13 04:47:20 UTC 2009",
    "deleted_at"=>"Tue Oct 13 04:47:20 UTC 2009",
    "id"=>569012001,
    "meta_keywords"=>"",
    "meta_description"=>"stock_id=1",
    "description"=>"Material-36 Mother of Africa<br /><br />Want to know more about who made this item? Click <a href=\"http://globalhandicrafts.org/Producers/tukul-craft/\" target=\"_blank\"> here</a>."}
end

def sample_stock_record
  {1 => {"Barcode"=>"SMBL6132",
 "track_serial"=>"0",
 "date_created"=>"Thu, 06 Mar 2008 22:56:09 +0000",
 "cost"=>38.2,
 "goods_tax"=>"N-T",
 "freight"=>"0",
 "PLU"=>0,
 "external"=>"0",
 "unitof_measure"=>false,
 "date_modified"=>"Tue, 16 Dec 2008 16:26:10 +0000",
 "order_threshold"=>"0.0",
 "quantity"=>"0.0",
 "inactive"=>"0",
 "custom1"=>"yes",
 "weighted"=>"0",
 "tare_weight"=>"0.0",
 "cat1"=>"ACCESS",
 "sales_prompt"=>"",
 "custom2"=>"",
 "picture_file_name"=>"",
 "order_quantity"=>"0.0",
 "static_quantity"=>"0",
 "sales_tax"=>"N-T",
 "cat2"=>"BAG",
 "longdesc"=>
  "multi colour w/overlap<br /><br />Want to know more about who made this item? Click <a href=\"http://globalhandicrafts.org/Producers/Bread_of_Life/\" target=\"_blank\"> here</a>.",
 "description"=>"Bag - woven multi colour w/overlap",
 "package"=>"0",
 "supplier_id"=>9,
 "salesorder_qty"=>"0.0",
 "layby_qty"=>"0.0",
 "sell"=>75.0,
 "print_components"=>"0",
 "stock_id"=>"1.0",
 "bonus"=>0.0,
 "allow_fractions"=>"0",
 "tax_components"=>"0",
 "allow_renaming"=>"0",
 "dept_id"=>1}}
end

def get_random_webstore_stock_id
  begin     # This code gets a random stock item that already will have been added to the webstore.
    random_id = rand($current_stock_records.size)
    key = $current_stock_records.keys[random_id]
  end while $current_stock_records[key]["custom1"].downcase != "yes"
  return $current_stock_records[key]["stock_id"].to_i
end

$LOG = Logger.new("ghicrafts_odbc_export.log", 10, 1024000)