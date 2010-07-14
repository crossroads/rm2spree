require "rubygems"
gem "dbd-odbc"
require 'dbi'
require 'digest/md5'
require 'logger'
require 'pp' 
require 'multipart_upload'
require "activeresource"
require "activesupport"
require 'net/http'
require 'net/smtp'
require 'smtp_tls' if VERSION =~ /1.8.6/ # Run ruby 1.8.6 on Windows, ruby 1.8.7 has smtp_tls baked in
require 'find'

$bootstrap = ARGV[1]


server_env = ARGV[0]


if not ["local", "preview", "beta", "live"].include? server_env
  puts "Wrong server environment argument. Should be 'local', 'preview', 'beta', or 'live'."
  exit
end

config_yaml = YAML.load_file("config_#{server_env}.yml")
Datasource_Name = config_yaml['datasource_name']
YAML_Records_Filename = config_yaml['yaml_records_filename'].gsub(".yml", "_#{server_env}.yml")
MD5_Records_Filename = config_yaml['md5_records_filename'].gsub(".yml", "_#{server_env}.yml")
Categories_Data_Filename = config_yaml['categories_filename'].gsub(".yml", "_#{server_env}.yml")
Spree_BaseURL = config_yaml['spree_baseurl']
(Spree_BaseURL.end_with? "/") ? Spree_BaseURL : Spree_BaseURL += "/"
Images_folder = config_yaml['images_folder']
Only_Images = config_yaml['only_images']
@spree_user = config_yaml['spree_user']
@spree_password = config_yaml['spree_password']

Enable_Emails = config_yaml['enable_emails']
Email_Server = config_yaml['email_server']
Email_User = config_yaml['email_user']
Email_Password = config_yaml['email_password']
Email_Port = config_yaml['email_port']
Email_Helo_Domain = config_yaml['email_helo_domain']
Email_To = config_yaml['email_to']

class Logger
  def info_x(message)
    puts message
    $LOG.info message
  end
  def debug_x(message)
    puts message
    $LOG.debug message
  end
    def error_x(message)
    puts message
    $LOG.error message
  end
end

class Array   # Defines a method on arrays to search for a taxonomy by its dept_id field.
  def find_taxonomy_id_by_dept(dept_id)
    self.each do |taxonomy|
      return taxonomy.id if taxonomy.myob_dept_id == dept_id
    end
    return nil
  end
  def find_taxon_id_by_cat_and_taxonomy(cat_id, taxonomy_id)
    self.each do |taxon|
      return taxon.id if taxon.myob_cat_id == cat_id && taxon.taxonomy_id == taxonomy_id
    end
    return nil
  end
end

class File
  def self.find(dir, filename="*.*", subdirs=true)
    Dir[ subdirs ? File.join(dir.split(/\\/), "**", filename) : File.join(dir.split(/\\/), filename) ]
  end
end

class Product_Sync < ActiveResource::Base
  self.site = Spree_BaseURL
  def self.find_by_stock_id(stock_id)
    self.find(:all).each { |product|
      if meta_desc = product.attributes["meta_description"]
        return product if meta_desc.split("=")[1].to_i == stock_id
      end
    }
    nil
  end
end

class Taxon_Sync < ActiveResource::Base
  self.site = Spree_BaseURL
end

class Taxonomy_Sync < ActiveResource::Base
self.site = Spree_BaseURL
end

[Product_Sync, Taxon_Sync, Taxonomy_Sync].each { |spree_api|      # Set user and password for each Active Resource class.
  spree_api.user = @spree_user
  spree_api.password = @spree_password
}

def write_or_load_data_if_file_exists(filename, data_to_write, return_flag)
  # If the script is running for the first time, (and files dont exist), populate the hash tables with the current data from MYOB RM.
  if File.exist?(filename)
    return YAML.load_file(filename)
  else
    $LOG.debug_x("\"#{filename}\" does not exist. Creating YAML file with data from current MYOB database.")
    File.open(filename, "w") do |f|
      f.write(data_to_write.to_yaml)
    end
    $LOG.debug_x("  - Wrote #{"md5 hash data"} data to YAML file at \"#{filename}\".")  
    if return_flag == true
      return data_to_write
    else
      return return_flag
    end
  end
end


def write_yaml_to_file(filename, data_to_write, data_type)
  # If the script is running for the first time, (and files dont exist), populate the hash tables with the current data from MYOB RM.
  $LOG.debug_x("Writing yaml data to file: \"#{filename}\"")
  File.open(filename, "w") do |f|
    f.write(data_to_write.to_yaml)
  end
  $LOG.debug_x("  - Wrote #{data_type} data to YAML file: \"#{filename}\".")  
end


def changeable_fields(record)
    record_data = ""
    %w(cost freight order_threshold quantity inactive custom1 custom2 \
    weighted tare_weight picture_file_name order_quantity static_quantity \
    cat1 longdesc description package supplier_id salesorder_qty layby_qty \
    sell print_components bonus tax_components allow_renaming dept_id).each { |field|
      record_data += record[1][field].to_s
    }
    record_data
end


def get_md5_hashes(stock_records)
  $LOG.debug_x("Creating md5 hashes from stock records.")
  md5_hash = {}
  stock_records.each { |record|
      record_data = changeable_fields(record)
      md5_hash[record[0]] = Digest::MD5.hexdigest(record_data)
  }
  return md5_hash
end

def get_category_md5_hashes(category_records)
  $LOG.debug_x("Creating md5 hashes from category records.")
  md5_hash = {}
  category_records.each { |id,string|
      md5_hash[id] = Digest::MD5.hexdigest(string)
  }
  return md5_hash
end


def compare_tables(value_hash, value_hash_old)
  value_changes = {}
  value_change_count = {:update => 0, :new => 0, :delete => 0}
  $LOG.debug_x("Scanning for record changes in database by comparing value hashes...")
  value_hash_old.each { |id, value|
    if value != value_hash[id]
      if value_hash[id] == nil
        value_changes[id] = :delete
        value_change_count[:delete] += 1
      else
        value_changes[id] = :update
        value_change_count[:update] += 1
      end
    end
  }
  value_hash.each { |id, value|
    if value != value_hash_old[id]
      if value_hash_old[id] == nil
        value_changes[id] = :new
        value_change_count[:new] += 1
      end
    end
  }
  if value_changes.size == 0
    $LOG.debug_x("  - Found no changes in hash tables.")
  else
    $LOG.debug_x(%Q":: Some stock records have been changed:
  - #{value_change_count[:update] } updated item(s)
  - #{value_change_count[:new] } new item(s)
  - #{value_change_count[:delete] } deleted item(s)")
  end
  return value_changes
end

def odbc_datasource(datasource)
    # Create an ODBC datasource connection
    #$LOG.debug_x("Attempting to connect to [DBI:ODBC:#{datasource}]...")
    db = DBI.connect("DBI:ODBC:#{datasource}")
    #$LOG.debug_x("  - Successfully connected to [DBI:ODBC:#{datasource}]")
    def db.disconnect_x
      #$LOG.debug_x(":: Disconnected from [DBI:ODBC:#{Datasource_Name}]")
      self.disconnect
    end
    return db
end

def fetch_stock_records()
  begin
    access_db = odbc_datasource(Datasource_Name)
    stock_fields_data = access_db.columns "Stock" # returns an array with the stock fields
    
    # Puts stock fields :name into an array
    stock_fields = []
    stock_fields_data.each { |item|
      stock_fields << item[:name]
    }

    $LOG.debug_x("  - Found list of field names from [Stock] table.")
    $LOG.debug_x("Querying all records from [Stock] table.")
    stock_data = access_db.select_all("SELECT * FROM \"Stock\" WHERE \"stock_id\" > 0")
    $LOG.debug_x("  - Fetched <#{stock_data.size}> records from [Stock] table.")
    # Create a hash of stock records with the field names as keys.stock
    
    stock_hash = {}
    stock_data.size.times do |i_item|
      stock_item_hash = Hash.new
      stock_fields.size.times do |i_field|
        stock_item_hash[stock_fields[i_field]] = stock_data[i_item][i_field]
      end
      stock_hash[stock_item_hash["stock_id"].to_i] = stock_item_hash
    end
    # Must convert each of [cost, sell, bonus] fields from ruby BigDecimal class to floating point, because BigDecimal doesnt play well with YAML.
    stock_hash.each do |id,value|
      %w{cost sell bonus}.each { |attribute|
        stock_hash[id][attribute] = stock_hash[id][attribute].to_f
      }
    end
    $LOG.debug_x("  - Created stock_data hash from data and field names, and sorted data.")
  rescue DBI::InterfaceError => e
       $LOG.error_x(%Q":: An error occurred: 
    #{e}")
      stock_hash = false
  ensure
      # disconnect from server
      access_db.disconnect_x if access_db
  end
  return stock_hash
end


def fetch_categories(table = "CategoryValues")
  #    stock_id  | dept_id | cat_id  | category_level  | catvalue_id
  begin
    # Create an ODBC datasource connection
    access_db = odbc_datasource(Datasource_Name)
    #~ category_data = access_db.select_all(%Q{
    #~ SELECT * FROM "CategoryValues" 
    #~ WHERE EXISTS (
      #~ SELECT * FROM "CategorisedStock" 
      #~ INNER JOIN "Stock" ON "CategorisedStock".stock_id = "Stock".stock_id
      #~ WHERE UCase(Trim("Stock".custom1)) = YES 
        #~ AND "CategoryValues".catvalue_id = "CategorisedStock".catvalue_id
    #~ )
  #~ })
  
  category_data = access_db.select_all("SELECT * FROM \"#{table}\"")
  
    category_hash = {}
    category_data.each { |category|
      category_hash[category[0]] = category[2]
    }
  rescue DBI::InterfaceError => e
    $LOG.error_x(%Q":: An error occurred: 
   #{e}")
    category_hash = false
  ensure
    access_db.disconnect_x if access_db
  end
  return category_hash
end


def fetch_departments()
  departments = fetch_categories("Departments")
  departments.delete(0)    # Return departments without the (0) index (remove "<default>" from hash)
  return departments
end


def fetch_categorised_values
  begin         # Department ID = Main category    # Category level 1 = sub-cat  # Category level 2 = ignore  # Category level 3 = ignore
    access_db = odbc_datasource(Datasource_Name)
    categorised_values = access_db.select_all("SELECT * FROM \"CategorisedValues\" WHERE \"cat_id\" = 1")
  rescue DBI::InterfaceError => e
    $LOG.error_x(%Q":: An error occurred: 
   #{e}")
    categorised_values = false
  ensure
    access_db.disconnect_x if access_db
  end
  return categorised_values
end


def find_category_by_stockid(stock_id)
  #    stock_id  | dept_id | cat_id  | category_level  | catvalue_id
  begin
    access_db = odbc_datasource(Datasource_Name)
    stock_category_data = access_db.select_all("SELECT * FROM \"CategorisedStock\" WHERE \"stock_id\" = #{stock_id} AND \"category_level\" = 2")
    stock_category_hash = {:dept_id => stock_category_data[0][1], :sub_cat => stock_category_data[0][4]}
  rescue DBI::InterfaceError => e
    $LOG.error_x(%Q":: An error occurred:
   #{e}")
    stock_category_hash = false
  ensure
    access_db.disconnect_x if access_db
  end
  return stock_category_hash
end


def find_category_details_by_catvalue_id(catvalue_id, categories, categorised_values)
  dept_hash = {}
  category_maps = []
  categorised_values.each { |section|
    category_maps << section if section[2] == catvalue_id
  }
  category_maps.each { |category|
    dept_hash[category[0]] = categories[:dept][category[0]] if category[0] != 0    #Find department name from department id (if department isnt 0)
  }
  category_details_hash = {:sub_cat=>catvalue_id, :cat_name=>categories[:cat1][catvalue_id], :dept_details=>dept_hash}
  return category_details_hash
end

def evaluate_stock_action_with_webstore(stock_action, web_store_old, web_store_current)
  case stock_action 
    when :update   # When the stock_action is believed to be an update ..
      if web_store_old  == "yes" && web_store_current != "yes"   # If it was a web-store product before and now it isnt,
        return :delete                                                # Then delete it from the web-store.
      end
      if web_store_old  != "yes" && web_store_current == "yes"   # If it wasn't a web-store product before and now it is ->
        return :new                                                   # Then add it to the web-store.
      end
      if web_store_old  != "yes" && web_store_current != "yes"     # If it never was a web-store product, then do nothing.
        return nil
      else
        return :update
      end
    when :delete    # When a record is found in old stock records that does not exist in the current stock records ..
      if web_store_old  != "yes"   # If its not a web-store product already,
        return nil        # Then don't bother deleting it because it was already deleted.
      else
        return :delete
      end
    when :new   # When a record is found in the current stock records that does not exist in the old stock records ..
      if web_store_current != "yes"    # If its not a web-store product,
        return nil              # Then don't add it to the web-store.
      else
        return :new
      end    
  end
end


def find_image(barcode)
  barcode = barcode.upcase
  dir = Images_folder + "\\" + barcode[0,1]
  image_path = nil
  Find.find(dir) do |path|
      if path.upcase.include?(barcode) and path.upcase.include?(".JPG")
        image_path = path.gsub("/","\\")
      end
  end
  image_path
end

def quantity_field(stock_id, stock_records)
  stock_records[stock_id]["quantity"].to_i
end

def get_product_data(stock_id, stock_records)
  product_data = {}
  product_data["name"] = stock_records[stock_id]["description"]
  product_data["description"] = stock_records[stock_id]["longdesc"]
  product_data["sku"] = stock_records[stock_id]["Barcode"].strip
  product_data["price"] = stock_records[stock_id]["sell"]
  product_data["available_on"]  = 1.day.ago
  product_data["meta_description"]  = "stock_id=#{stock_id}"
  product_data["on_hand"] = stock_records[stock_id]["quantity"]
  weight = stock_records[stock_id]["custom2"].to_f
  weight = (weight > 0 && weight < 10) ? weight : nil     # Valid weights are a numeric value greater than 0 and less than 5 kg.
  product_data["weight"] = weight
  #product_data["shipping_category_id"]
  product_data
end


def add_spree_product(product_data)
  # If it was previously deleted (unsure how to test this)  then  set 'deleted_at' flag to nil
  $LOG.debug_x("Adding new product to web-store with #{product_data["meta_description"]}")    # log the stock_id from metadesc...
  new_product = Product_Sync.new(product_data)
    if new_product.save
      $LOG.debug_x("  - Product was successfully added to web-store. [product_id = #{new_product.permalink}]")
      new_product
    else 
      $LOG.error_x(":: Error: Product could not be added to the web-store.")
      $LOG.error_x(new_product.errors.errors)          # If there was an error while uploading the product...
      false
    end
end


def update_spree_product(stock_id, stock_records_new, stock_records_old)
	$LOG.debug_x("Updating product in web-store with stock_id: #{stock_id}")
	update_product = Product_Sync.find_by_stock_id(stock_id)
	product_data = get_product_data(stock_id, stock_records_new)
	cat_id = find_category_by_stockid(stock_id)[:sub_cat]
	dept_id = stock_records_new[stock_id]["dept_id"]
	taxonomy_id = @spree_taxonomies.find_taxonomy_id_by_dept(dept_id)
	product_data["taxon_id"] = @spree_taxons.find_taxon_id_by_cat_and_taxonomy(cat_id, taxonomy_id)
	if update_product == nil
		$LOG.error_x(":: Error: Product could not be found in Spree database. [stock_id = #{stock_id}]")
		return false
	else
		# Upload image if it has changed from 'not existing' to 'existing'.
	  if image_field(stock_id, stock_records_new) != image_field(stock_id, stock_records_old)
		image_path = find_image(@stock_records_current[stock_id]["Barcode"])
		upload_image(image_path, update_product.attributes["permalink"])    
	  end
	  if quantity_field(stock_id, stock_records_old) > 0 && quantity_field(stock_id, stock_records_new) == 0  # If quantity was greater than 0 and is now 0 ->
		update_product.deleted_at = Time.now   # Set 'deleted_at' to Time.now
	  end
	  if quantity_field(stock_id, stock_records_old) == 0 && quantity_field(stock_id, stock_records_new) > 0  # If quantity was 0 and is now greater than 0 ->
		update_product.deleted_at = nil    # Set 'deleted_at' to nil
	  end      
	  update_product.attributes.merge!(product_data)  # Overwrite product data with new values.
	  update_product.save
	  return update_product
	end
	rescue
		$LOG.error_x(":: Error: There was an error while updating product in Spree database.")
		return false
end


def delete_spree_product(stock_id)
  begin
    delete_product = Product_Sync.find_by_stock_id(stock_id)
    delete_product.deleted_at = Time.now
    delete_product.save
    return true
  rescue
    $LOG.error_x(":: Error: There was an error while deleting product from Spree database.")
    return false
  end
end


def add_spree_category(taxon_data, taxon_type)
  begin
    case taxon_type
      when :taxon
        $LOG.debug_x("Adding new category to spree: \"#{taxon_data["name"]}\"")
        new_taxon = Taxon_Sync.new(taxon_data)
        new_taxon.save
        $LOG.debug_x(%Q"  - Taxon was successfully added to spree app. [id = #{new_taxon.object_id}]
  - added to taxonomy_id: #{taxon_data["taxonomy_id"]}")
      when :taxonomy
        $LOG.debug_x("Adding new department to spree: \"#{taxon_data["name"]}\"")
        new_taxon = Taxonomy_Sync.new(taxon_data)
        new_taxon.save
        $LOG.debug_x("  - Taxonomy was successfully added to spree app. [id = #{new_taxon.object_id}]")
    end
      return new_taxon
  rescue
    if new_taxon.errors.errors          # If there was an error while uploading the product...
      $LOG.error_x(":: Error: Taxon could not be added to spree app.")
    end
    return false
  end
end


def upload_image(image_file, product_id)
  begin    
    $LOG.debug_x(%Q"Uploading image to [#{Spree_BaseURL}]...
  - Image_file: #{image_file.split("\\").last}
  - Product_name: #{product_id}")
    url_string = "#{Spree_BaseURL}admin/products/#{product_id}/images"
    m = Multipart.new 'image[attachment]' => image_file
    m.post(url_string, "image/jpeg", @spree_user, @spree_password)
    $LOG.debug_x("  - Image was successfully uploaded!")
    return true
  rescue
    $LOG.error_x(":: Error: Product image could not be uploaded.")
    return false
  end
end


def send_error_email(errors_for_email)
  begin
    $LOG.debug_x("Sending error report email to [#{Email_To}]...\n  (#{errors_for_email.size} errors in total.)")
    if Enable_Emails
      email_from = Email_User
      subject = "MYOB Synchronization warning: Some categories must be manually updated."
            
      message_body = "It looks like you have updated some categories in MYOB recently.\nThe Spree web-store synchronization script does not know how to handle some of these changes.\nPlease see below for the list of changes:\n\n\n"
      errors_for_email.each do |id, error|
        message_body << "'#{error[:message]}'\n"
        message_body << "            [ID] : #{id}\n"
        message_body << "[Previous state] : #{error[:previous_state]}\n"
        message_body << "     [New state] : #{error[:new_state]}\n\n"
      end
      
      message_body << "\n\nPlease contact the system administrator if you are unable to resolve these conflicts.\nIf there has been a major change to the categories in MYOB, a database remigration may be in order."
      
      $LOG.debug_x("-- Email body:\n{{\n#{message_body}\n}}\n")
      
      message_header = ''
      message_header << "From: <#{email_from}>\r\n"
      message_header << "To: <#{Email_To}>\r\n"
      message_header << "Subject: #{subject}\r\n"
      message_header << "Date: " + Time.now.to_s + "\r\n"
      message = message_header + "\r\n" + message_body + "\r\n"

      smtp = Net::SMTP.new(Email_Server, Email_Port)
      smtp.enable_starttls
      smtp.start(Email_Helo_Domain,
                 Email_User,
                 Email_Password,
                 :plain) do |smtp_connection|
        smtp_connection.send_message message, email_from, Email_To
      end
      $LOG.debug_x("  - Error report email sent.")
      return message
    end
  rescue
    return false
  end
end
