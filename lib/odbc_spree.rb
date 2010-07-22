require "rubygems"
gem "dbd-odbc"
require 'dbi'
require 'digest/md5'
require 'logger'
require 'pp'
require File.join('lib', 'multipart_upload')
require "active_resource"
require "active_support"
require 'net/http'
require 'net/smtp'
require 'smtp_tls' if VERSION =~ /1.8.6/ # Run ruby 1.8.6 on Windows, ruby 1.8.7 has smtp_tls baked in
require 'find'

Logger.class_eval do
  alias :log_info :info
  alias :log_debug :debug
  alias :log_error :error

  def info(message)
    puts message
    log_info(message)
  end
  def debug(message)
    puts message
    log_debug(message)
  end
  def error(message)
    puts message
    log_error(message)
  end
end

module Spree
  module ODBC
    class RM
      attr_accessor :log,
                    :spree_baseurl,
                    :categories_current,
                    :categories_old,
                    :md5_hash_current,
                    :md5_hash_old,
                    :categorised_values,
                    :stock_records_current,
                    :stock_records_old,
                    :spree_taxonomies,
                    :spree_taxons

      def initialize(env, bootstrap = false)
        @env = env

        # Load test config for spec.
        if env == "test" or env == "config"
          config = YAML.load_file(File.join("spec", "config_test.yml"))
        else
          config = YAML.load_file(File.join("config", "config_#{env}.yml"))
        end

        config.each do |key, value|
          instance_variable_set("@#{key}", value)
        end

        @spree_baseurl += "/" unless @spree_baseurl.end_with? "/"

        # Add the spree env to filenames
        @yaml_records_filename.gsub!(".yml", "_#{env}.yml")
        @md5_records_filename.gsub!(".yml", "_#{env}.yml")
        @categories_filename.gsub!(".yml", "_#{env}.yml")

        # Set site, user and password for each Active Resource class.
        [ProductSync, TaxonSync, TaxonomySync].each { |api|
          api.site = @spree_baseurl
          api.user = @spree_user
          api.password = @spree_password
        }

        @log = logger

        # Clear all old saved data if we are bootstrapping
        if bootstrap
          [@yaml_records_filename,
          @md5_records_filename,
          @categories_filename].each do |path|
            File.delete(path) if File.exist?(path)
          end
        end

        # Load valid product barcodes (with proofed
        # descriptions). If the yaml file doesnt exist,
        # the script will treat all products as valid.
        @valid_products = YAML.load_file('config/valid_products.yml').map{|s| s.strip.upcase } rescue :all

        connect if @env=="test"
      end

      def logger
        if @env == "test"
          MockLogger.new
        else
          l = Logger.new(File.join("log", "odbc_export_#{@env}.log"), 10, 1024000)
          l.formatter = Logger::Formatter.new
          l.formatter.datetime_format = "%Y-%m-%d %H:%M:%S"
          l
        end
      end

      def connect
        # Initialize an ODBC datasource connection
        @access_db = odbc_datasource(@datasource_name)
      end

      #-------------------------------------------------------
      #                    File methods
      #-------------------------------------------------------

      def load_file_with_defaults(filename, default)
        # If the file doesn't exist, return default (empty) data.
        if File.exist?(filename)
          YAML.load_file(filename)
        else
          default
        end
      end

      def write_yaml_to_file(filename, data_to_write)
        # If the script is running for the first time, (and files dont exist), populate the hash tables with the current data from MYOB RM.
        @log.debug("=== Writing YAML file: \"#{filename}\"...")
        File.open(filename, "w") do |f|
          f.write(data_to_write.to_yaml)
        end
      end

      def save_stock_data_to_files
        write_yaml_to_file(@md5_records_filename, @md5_hash_current)
        write_yaml_to_file(@yaml_records_filename, @stock_records_current)
      end

      def save_categories_data_to_files
        write_yaml_to_file(@categories_filename, @categories_current)
      end

      #-------------------------------------------------------
      #                   ODBC Data Retrieval
      #-------------------------------------------------------

      def odbc_datasource(datasource)
        # Create an ODBC datasource connection
        #@log.debug("Attempting to connect to [DBI:ODBC:#{datasource}]...")
        db = DBI.connect("DBI:ODBC:#{datasource}")
        #@log.debug("  - Successfully connected to [DBI:ODBC:#{datasource}]")
        def db.disconnect_x
          #@log.debug(":: Disconnected from [DBI:ODBC:#{@datasource_name}]")
          self.disconnect
        end
        return db
      end

      def fetch_current_data
        @categories_current = {}
        @categories_current[:dept] = fetch_departments
        @categories_current[:cat1] = fetch_categories
        @categorised_values = fetch_categorised_values
        @stock_records_current = fetch_stock_records
        @md5_hash_current = get_md5_hashes(@stock_records_current)
      end

      def fetch_old_data
        @categories_old    = load_file_with_defaults(@categories_filename, {:dept => {}, :cat1 => {}})
        @stock_records_old = load_file_with_defaults(@yaml_records_filename, @stock_records_current)
        @md5_hash_old      = load_file_with_defaults(@md5_records_filename, {})
      end

      def fetch_stock_records()
        stock_fields_data = @access_db.columns "Stock" # returns an array with the stock fields

        # Puts stock fields :name into an array
        stock_fields = []
        stock_fields_data.each { |item|
          stock_fields << item[:name]
        }

        @log.debug("  - Found list of field names from [Stock] table.")
        @log.debug("Querying all records from [Stock] table.")
        stock_data = @access_db.select_all("SELECT * FROM \"Stock\" WHERE \"stock_id\" > 0")
        @log.debug("  - Fetched <#{stock_data.size}> records from [Stock] table.")
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
        @log.debug("  - Created stock_data hash from data and field names, and sorted data.")

        stock_hash

        rescue DBI::InterfaceError => e
          @log.error(":: An error occurred: \n#{e}")
          return false
      end

      def fetch_categories(table = "CategoryValues")
        category_data = @access_db.select_all("SELECT * FROM \"#{table}\"")
          category_hash = {}
          category_data.each { |category|
            category_hash[category[0]] = category[2]
          }
        category_hash

        rescue DBI::InterfaceError => e
          @log.error(%Q":: An error occurred:
         #{e}")
          category_hash = false
      end


      def fetch_departments(table = "Departments")
        category_data = @access_db.select_all("SELECT * FROM \"#{table}\"")
        category_hash = {}
        category_data.each { |category|
          category_hash[category[0]] = category[2]
        }
        # Return departments without the (0) index
        # (remove "<default>" from the hash)
        category_hash.delete(0)

        category_hash

        rescue DBI::InterfaceError => e
          @log.error(%Q":: An error occurred:
         #{e}")
          category_hash = false
      end


      def fetch_categorised_values
        # Department ID = Main category
        # Category level 1 = sub-cat
        # Category level 2 = ignore
        # Category level 3 = ignore

        categorised_values = @access_db.select_all("SELECT * FROM \"CategorisedValues\" WHERE \"cat_id\" = 1")

        rescue DBI::InterfaceError => e
          @log.error(%Q":: An error occurred:
         #{e}")
          categorised_values = false

        return categorised_values
      end

      def find_category_by_stockid(stock_id)
        # stock_id, dept_id, cat_id, category_level, catvalue_id
        stock_category_data = @access_db.select_all("SELECT * FROM \"CategorisedStock\" WHERE \"stock_id\" = #{stock_id} AND \"category_level\" = 2")
        stock_category_hash = {:dept_id => stock_category_data[0][1],
                               :sub_cat => stock_category_data[0][4]}
        rescue DBI::InterfaceError => e
          @log.error(%Q":: An error occurred:
         #{e}")
          stock_category_hash = false
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
        category_details_hash = {:sub_cat  => catvalue_id,
                                 :cat_name => categories[:cat1][catvalue_id],
                                 :dept_details => dept_hash}
        return category_details_hash
      end

      #-------------------------------------------------------
      #                    Data Comparison
      #-------------------------------------------------------

      def changeable_fields(record)
          record_data = ""
          %w(cost freight order_threshold quantity inactive
          custom1 custom2 weighted tare_weight picture_file_name
          order_quantity static_quantity cat1 longdesc
          description package supplier_id salesorder_qty
          layby_qty sell print_components bonus tax_components
          allow_renaming dept_id).each { |field|
            record_data += record[1][field].to_s
          }
          record_data
      end

      def get_md5_hashes(stock_records)
        md5_hash = {}
        stock_records.each { |record|
            record_data = changeable_fields(record)
            md5_hash[record[0]] = Digest::MD5.hexdigest(record_data)
        }
        return md5_hash
      end

      def get_category_md5_hashes(category_records)
        md5_hash = {}
        category_records.each { |id,string|
            md5_hash[id] = Digest::MD5.hexdigest(string)
        }
        return md5_hash
      end

      def compare_tables(value_hash, value_hash_old)
        value_changes = {}
        value_change_count = {:update => 0, :new => 0, :delete => 0}
        @log.debug("Scanning for record changes in database by comparing value hashes...")
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
          @log.debug("  - Found no changes in hash tables.")
        else
          @log.debug(%Q":: Some stock records have been changed:
        - #{value_change_count[:update] } updated item(s)
        - #{value_change_count[:new] } new item(s)
        - #{value_change_count[:delete] } deleted item(s)")
        end
        return value_changes
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

      #-------------------------------------------------------
      #                  Comparison actions
      #-------------------------------------------------------

      def process_department_change(id, action, errors_for_email)
        case action
        when :update
          errors_for_email[id] = {:message =>
%Q"A department name has been updated.
It might need to be also renamed on the web-store.",
                                  :previous_state => @categories_old[:dept][id],
                                  :new_state => @categories_curent[:dept][id]}

        when :new
          taxonomy_data = {"name" => @categories_current[:dept][id].capitalize,
                                    "myob_dept_id" => id}
          if add_spree_category(taxonomy_data, :taxonomy)
          end

        when :delete
          errors_for_email[id] = {:message =>
%Q"A department has been deleted.
It might need to be removed from the webstore,
and corresponding products might need to be updated.",
                         :previous_state => @categories_old[:dept][id],
                         :new_state => "## DELETED"}
        end
      end

      def process_category_change(id, action, errors_for_email)
        case action
        when :update    # Ignore string value updates. We only care about category ids being added or deleted.
          errors_for_email[id] = {:message => "A category name has been updated. It might need to be also renamed on the web-store.",
                                       :previous_state => @categories_old[:cat1][id],
                                       :new_state => @categories_curent[:cat1][id]}
        when :new
          category_details = find_category_details_by_catvalue_id(id, @categories_current, @categorised_values)
            # Reasons to not add a category : its name is "<N/A>", or it belongs to no departments.
            if category_details[:cat_name] != "<N/A>" && category_details[:dept_details] != {} then
              category_details[:dept_details].each { |department|         # add the category to each department it belongs to...
                taxonomy_id = @spree_taxonomies.find_taxonomy_id_by_dept(department[0])    # Find the spree taxonomy id for the given department.
                taxon_data = {"name" => category_details[:cat_name].capitalize,
                                     "taxonomy_id" => taxonomy_id,
                                     "parent_id" => taxonomy_id,
                                    "myob_cat_id" => id}
                add_spree_category(taxon_data, :taxon)
              }
            end
        when :delete    # Dont touch Spree, just send an email to notify administrator of change.
          errors_for_email[id] = {:message =>
%Q"A category has been deleted.
It might need to be removed from the webstore,
and corresponding products might need to be updated.",
                         :previous_state => @categories_old[:cat1][id],
                         :new_state => "## DELETED"}
        end
      end

      def process_stock_change(stock_id, stock_action, action_count)
        # Unless there is at least one record matching the stock_id, ignore the entire stock_action.
        if @stock_records_old[stock_id] || @stock_records_current[stock_id]

          web_store_current = @stock_records_current[stock_id]["custom1"].downcase.strip     # .downcase the value, because it could be
          web_store_old = @stock_records_old[stock_id]["custom1"].downcase.strip                 # either "Yes" or "yes"
          stock_action = evaluate_stock_action_with_webstore(stock_action,
                                                             web_store_old,
                                                             web_store_current)

          case stock_action
            when :new                   # If the product is a new product to be added to the web-store
              image_path = find_image(@stock_records_current[stock_id]["Barcode"])

              if ((@only_images and image_path) or !@only_images) and
                 (@valid_products == :all or @valid_products.include?(@stock_records_current[stock_id]["Barcode"].strip.upcase))

                cat_id = find_category_by_stockid(stock_id)[:sub_cat]
                dept_id = @stock_records_current[stock_id]["dept_id"]
                taxonomy_id = @spree_taxonomies.find_taxonomy_id_by_dept(dept_id)
                new_product_data = get_product_data(stock_id, @stock_records_current)

                if taxon_id = @spree_taxons.find_taxon_id_by_cat_and_taxonomy(cat_id, taxonomy_id)
                  new_product_data["taxon_id"] = taxon_id
                  if new_product_data["weight"] != nil    # Only add products that have feasible weights.
                    if new_product = add_spree_product(new_product_data)    # if the function returns true...
                      action_count[:new] += 1
                      if image_path # If there is an image for the new product, then upload it to the web-store.
                        if upload_image(image_path, new_product.permalink)
                          action_count[:image] += 1
                        end
                      else
                        @log.debug("  - Product did not have an image. Not uploaded.")
                      end
                    else                                        # otherwise if 'add_spree_product' function returns false
                      action_count[:error] += 1
                    end
                  end
                else  #else if taxon_id = nil
                  @log.error(":: Error: Taxon ID could not be found.")
                  action_count[:error] += 1
                end
              else
                action_count[:ignore_image] += 1
              end
            when :update          # If the product has already been added to the web-store but needs to be updated...
              if update_spree_product(stock_id, @stock_records_current, @stock_records_old)
                action_count[:update] += 1
              else
                action_count[:error] += 1
              end
            when :delete           # If the product has been added to the web-store but needs to be deleted
              @log.debug("Deleting product from web-store with stock_id: #{stock_id}")
              if delete_spree_product(stock_id)
                action_count[:delete] += 1
              else                                        # otherwise if the function returns false
                action_count[:error] += 1
              end
            when nil
              action_count[:ignore] += 1      # If there is an action to do ->
          end
        end
      end

      #-------------------------------------------------------
      #                       Images / Other
      #-------------------------------------------------------

      def find_image(barcode)
        barcode = barcode.upcase
        dir = @images_folder + "\\" + barcode[0,1]
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

      #-------------------------------------------------------
      #                 Spree REST API methods
      #-------------------------------------------------------

      def get_spree_taxonomies
        @spree_taxonomies = TaxonomySync.find(:all)
      end

      def get_spree_taxons
        @spree_taxons = TaxonSync.find(:all)
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
        # Cannot add a product without a taxon.
        return false unless product_data["taxon_id"]
        # If it was previously deleted (unsure how to test this)  then  set 'deleted_at' flag to nil
        @log.debug("Adding new product to web-store with #{product_data["meta_description"]}")    # log the stock_id from metadesc...
        new_product = ProductSync.new(product_data)
        if new_product.save
          @log.debug("  - Product was successfully added to web-store. [product_id = #{new_product.permalink}]")
          new_product
        else
          @log.error(":: Error: Product could not be added to the web-store.")
          @log.error(new_product.errors.errors)          # If there was an error while uploading the product...
          false
        end
      end


      def update_spree_product(stock_id, stock_records_new, stock_records_old)
	      @log.debug("Updating product in web-store with stock_id: #{stock_id}")
	      update_product = ProductSync.find_by_stock_id(stock_id)
	      product_data = get_product_data(stock_id, stock_records_new)
	      cat_id = find_category_by_stockid(stock_id)[:sub_cat]
	      dept_id = stock_records_new[stock_id]["dept_id"]
	      taxonomy_id = @spree_taxonomies.find_taxonomy_id_by_dept(dept_id)
	      product_data["taxon_id"] = @spree_taxons.find_taxon_id_by_cat_and_taxonomy(cat_id, taxonomy_id)
	      if update_product == nil
		      @log.error(":: Error: Product could not be found in Spree database. [stock_id = #{stock_id}]")
		      return false
	      else

		      #TODO - need to sort out how to find if images are updated.

		      # Upload image if it has changed from 'not existing' to 'existing'.
#	        if image_field(stock_id, stock_records_new) != image_field(stock_id, stock_records_old)
#		        image_path = find_image(@stock_records_current[stock_id]["Barcode"])
#		        upload_image(image_path, update_product.attributes["permalink"])
#	        end

	        if quantity_field(stock_id, stock_records_old) > 0 && quantity_field(stock_id, stock_records_new) == 0  # If quantity was greater than 0 and is now 0 ->
		        update_product.deleted_at = Time.now   # Set 'deleted_at' to Time.now
	        end
	        if quantity_field(stock_id, stock_records_old) == 0 && quantity_field(stock_id, stock_records_new) > 0  # If quantity was 0 and is now greater than 0 ->
		        # Set 'deleted_at' to nil
		        update_product.deleted_at = nil
	        end
          # Overwrite product data with new values.
	        update_product.attributes.merge!(product_data)
	        update_product.save
	        return update_product
	      end
	      rescue StandardError => e
		      @log.error(":: Error: There was an error while updating product in Spree database: \n#{e}")
		      return false
      end


      def delete_spree_product(stock_id)
        delete_product = ProductSync.find_by_stock_id(stock_id)
        delete_product.deleted_at = Time.now
        delete_product.save
        true
        rescue StandardError => e
          @log.error(":: Error: There was an error while deleting product from Spree database: \n#{e}")
          false
      end


      def add_spree_category(taxon_data, taxon_type)
        case taxon_type
        when :taxon
          @log.debug("Adding new category to spree: \"#{taxon_data["name"]}\"")
          new_taxon = TaxonSync.new(taxon_data)
          new_taxon.save
          @log.debug(
%Q"Taxon was successfully added to spree app.
[id = #{new_taxon.object_id}]
-- added to taxonomy_id: #{taxon_data["taxonomy_id"]}")
        when :taxonomy
          @log.debug("Adding new department to spree: \"#{taxon_data["name"]}\"")
          new_taxon = TaxonomySync.new(taxon_data)
          new_taxon.save
          @log.debug("  - Taxonomy was successfully added to spree app. [id = #{new_taxon.object_id}]")
        end

        return new_taxon

        rescue StandardError => e
          if new_taxon.errors.errors          # If there was an error while uploading the product...
            @log.error(":: Error: Taxon could not be added to spree app: \n#{e}")
          end
          return false
      end

      def upload_image(image_file, product_id)
        @log.debug(%Q"Uploading image to [#{@spree_baseurl}]...
      - Image_file: #{image_file.split("\\").last}
      - Product_name: #{product_id}")
        url_string = "#{@spree_baseurl}admin/products/#{product_id}/images"
        m = Multipart.new 'image[attachment]' => image_file
        m.post(url_string, "image/jpeg", @spree_user, @spree_password)
        @log.debug("  - Image was successfully uploaded!")
        return true
        rescue StandardError => e
          @log.error(":: Error: Product image could not be uploaded: \n#{e}")
          return false
      end

      #-------------------------------------------------------
      #                   Error Emails
      #-------------------------------------------------------

      def send_error_email(errors_for_email)
        @log.debug("Sending error report email to [#{@email_to}]...\n  (#{errors_for_email.size} errors in total.)")
        if @enable_emails
          email_from = @email_user
          subject = "MYOB Synchronization warning: Some categories must be manually updated."

          message_body =
      %Q"It looks like you have updated some categories in MYOB recently.
      The Spree web-store synchronization script does not know
      how to handle this.
      Please see below for the list of changes:


      "
          errors_for_email.each do |id, error|
            message_body << "'#{error[:message]}'\n"
            message_body << "            [ID] : #{id}\n"
            message_body << "[Previous state] : #{error[:previous_state]}\n"
            message_body << "     [New state] : #{error[:new_state]}\n\n"
          end

          message_body << "\n\nPlease contact the system administrator if you are unable to resolve these conflicts.\nIf there has been a major change to the categories in MYOB, a database remigration may be in order."

          @log.debug("-- Email body:\n{{\n#{message_body}\n}}\n")

          message_header = ''
          message_header << "From: <#{email_from}>\r\n"
          message_header << "To: <#{@email_to}>\r\n"
          message_header << "Subject: #{subject}\r\n"
          message_header << "Date: " + Time.now.to_s + "\r\n"
          message = message_header + "\r\n" + message_body + "\r\n"

          smtp = Net::SMTP.new(@email_server, @email_port)
          smtp.enable_starttls
          smtp.start(@email_helo_domain,
                     @email_user,
                     @email_password,
                     :plain) do |smtp_connection|
            smtp_connection.send_message message, email_from, @email_to
          end
          @log.debug("  - Error report email sent.")
          return message
        end
        rescue StandardError => e
          @log.error(":: Error report email could not be sent: \n#{e}")
          return false
      end

    end
  end
end


# --------- Set up ActiveResource classes

class ProductSync < ActiveResource::Base
  def self.find_by_stock_id(stock_id)
    self.find(:all).each { |product|
      if meta_desc = product.attributes["meta_description"]
        return product if meta_desc.split("=")[1].to_i == stock_id
      end
    }
    nil
  end
end
class TaxonSync < ActiveResource::Base; end
class TaxonomySync < ActiveResource::Base; end

# --------- Patches for various classes

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

