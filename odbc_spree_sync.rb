require "odbc_spree_functions"

Start_Time = Time.now
$LOG = Logger.new("odbc_export.log", 10, 1024000)
$LOG.formatter = Logger::Formatter.new
$LOG.formatter.datetime_format = "%Y-%m-%d %H:%M:%S"
$LOG.debug_x("\n\n -=- MYOB Database Synchronization Script started. -=- \n")

# ------ Begin Code Execution -------

@categories_current = {}
@categories_current[:dept] = fetch_departments
@categories_current[:cat2] = fetch_categories
@categorised_values = fetch_categorised_values
@stock_records_current = fetch_stock_records
@md5_hash_current = get_md5_hashes(@stock_records_current)

# Clear all current data if we are (re)bootstrapping
if $bootstrap
  File.delete Categories_Data_Filename if File.exist? Categories_Data_Filename
  File.delete YAML_Records_Filename if File.exist? YAML_Records_Filename
  File.delete MD5_Records_Filename if File.exist? MD5_Records_Filename
end


@categories_old = write_or_load_data_if_file_exists(Categories_Data_Filename, @categories_current, {:dept => {}, :cat2 => {}})
@stock_records_old =  write_or_load_data_if_file_exists(YAML_Records_Filename, @stock_records_current, true)
@md5_hash_old = write_or_load_data_if_file_exists(MD5_Records_Filename, @md5_hash_current, {})

$LOG.debug_x("\n -=- Script has run for the first time. Uploading all product data to spree. -=- \n") if @md5_hash_old == {} or $bootstrap

$LOG.debug_x("== Scanning for Department changes ...")
department_changes = {:dept => compare_tables(@categories_current[:dept], @categories_old[:dept])}
$LOG.debug_x("== Scanning for Category changes ...")
category_changes = {:cat2 => compare_tables(@categories_current[:cat2], @categories_old[:cat2])}
$LOG.debug_x("== Scanning for Stock changes ...")
stock_changes = compare_tables(@md5_hash_current, @md5_hash_old)

# Merge department and category changes together.
category_changes.merge!(department_changes)
errors_for_email = []

#~ @no_images = []
#~ @have_images = []

#~ @stock_records_current.each do |stock_id, record|
  #~ if record["custom1"].downcase == "yes" 
    #~ if find_image(record["Barcode"])
      #~ @have_images << record["Barcode"]
    #~ else
      #~ @no_images << record["Barcode"]
    #~ end
  #~ end
#~ end

#~ $LOG.debug_x(%Q"

#~ :: Checking for web store products without images:
     #~ - No images count:  #{@no_images.size}
     #~ - Have images count:  #{@have_images.size}
     #~ - Total web store proudcts: #{@have_images.size + @no_images.size}
#~ ")


[:dept, :cat2].each do |cat_type|               # Update departments first, and THEN second level categories.
  
  @spree_taxonomies = Taxonomy_Sync.find(:all) if cat_type == :cat2
  
  if category_changes[cat_type].size > 0
    category_changes[cat_type].each { |id, action|     # If there were any category changes, push them to Spree.
      case cat_type
        when :dept
          case action
            when :update
              errors_for_email[id] = {:message => "A department name has been updated. It might need to be also renamed on the web-store.",
                                           :previous_state => @categories_old[:dept][id],
                                           :new_state => @categories_curent[:dept][id]}
            when :new
              taxonomy_data = {"name" => @categories_current[:dept][id].capitalize,
                                        "myob_dept_id" => id}
              if add_spree_category(taxonomy_data, :taxonomy)
              end
            when :delete
              errors_for_email[id] = {:message => "A department has been deleted. It might need to be removed from the webstore, and corresponding products might need to be updated.",
                             :previous_state => @categories_old[:dept][id],
                             :new_state => "## DELETED"}
          end
        when :cat2
            # Fetch all taxonomies from Spree.
            case action
              
              when :update    # Ignore string value updates. We only care about category ids being added or deleted.
                errors_for_email[id] = {:message => "A category name has been updated. It might need to be also renamed on the web-store.",
                                             :previous_state => @categories_old[:cat2][id],
                                             :new_state => @categories_curent[:cat2][id]}            
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
                errors_for_email[id] = {:message => "A category has been deleted. It might need to be removed from the webstore, and corresponding products might need to be updated.",
                               :previous_state => @categories_old[:cat2][id],
                               :new_state => "## DELETED"}
              end
          Taxon_Sync.find("translate")  # Sends a get request to the server, which triggers the 'translate taxons' method.
        end
    }

  end
end


send_error_email(errors_for_email) if errors_for_email != []

action_count = {:new => 0,
                       :update => 0,
                       :delete => 0,
                       :image => 0,
                       :ignore => 0,
                       :ignore_image => 0,
                       :error => 0}

@spree_taxons = Taxon_Sync.find(:all)

depts = {}
taxonomys = {}
taxons = {}

if stock_changes.size > 0  # If there were any record changes, push them to Spree.
  stock_changes.each do |stock_id, stock_action|
    # Unless there is at least one record matching the stock_id, ignore the entire stock_action.
    if @stock_records_old[stock_id] || @stock_records_current[stock_id]
      
      web_store_current = @stock_records_current[stock_id]["custom1"].downcase.strip     # .downcase the value, because it could be
      web_store_old = @stock_records_old[stock_id]["custom1"].downcase.strip                 # either "Yes" or "yes"
      stock_action = evaluate_stock_action_with_webstore(stock_action, web_store_old, web_store_current)
      
      case stock_action
        when :new                   # If the product is a new product to be added to the web-store
          image_path = find_image(@stock_records_current[stock_id]["Barcode"])
          if (Only_Images && image_path) || !Only_Images

            cat_id = find_category_by_stockid(stock_id)[:sub_cat]
            dept_id = @stock_records_current[stock_id]["dept_id"]
            taxonomy_id = @spree_taxonomies.find_taxonomy_id_by_dept(dept_id)
            new_product_data = get_product_data(stock_id, @stock_records_current)
            
            if taxon_id = @spree_taxons.find_taxon_id_by_cat_and_taxonomy(cat_id, taxonomy_id)
              new_product_data["taxon_id"] = taxon_id
            else  #else if taxon_id = nil
              $LOG.error_x(":: Error: Taxon ID could not be found.")
            end
            
            if new_product_data["weight"] != nil    # Only add products that have feasible weights.
              if new_product = add_spree_product(new_product_data)    # if the function returns true...
                action_count[:new] += 1
                if image_path # If there is an image for the new product, then upload it to the web-store.
                  if upload_image(image_path, new_product.permalink)
                    action_count[:image] += 1
                  end
                else
                  $LOG.debug_x("  - Product did not have an image. Not uploaded.")
                end
              else                                        # otherwise if 'add_spree_product' function returns fals
                action_count[:error] += 1
              end
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
          $LOG.debug_x("Deleting product from web-store with stock_id: #{stock_id}")
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
  
  # Update the saved record files to current MYOB record data.
  $LOG.debug_x("Saving updated records and MD5 hashes to disk...")
  write_yaml_to_file(MD5_Records_Filename, @md5_hash_current, "md5 hash data")
  write_yaml_to_file(YAML_Records_Filename, @stock_records_current, "stock record data")
  write_yaml_to_file(Categories_Data_Filename, @categories_current, "categories data")
end

$LOG.debug_x(%Q"

:: MYOB Database Synchronization Script has finished.
  -- Completed in #{Time.now - Start_Time} seconds.
               -- (#{'%.3f' % ((Time.now - Start_Time) / 60)} minutes.)
     - Added #{action_count[:new]} product(s) to the web-store.
        - Ignored #{action_count[:ignore_image]} product(s) that did not have images to upload.
        - There were #{action_count[:new] + action_count[:ignore_image]} product(s) available for the webstore.
     - Updated #{action_count[:update]} product(s) in the web-store.
     - Deleted #{action_count[:delete]} product(s) from the web-store.
     - Uploaded #{action_count[:image]} image(s) to products in the web-store.
     - Ignored #{action_count[:ignore]} product(s) that were not web-store related.
     - There were #{action_count[:error]} total errors.
")