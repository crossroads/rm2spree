#!/usr/bin/env ruby
env, bootstrap = ARGV[0], ARGV[1]

if not ["test", "local", "preview", "beta", "live"].include? env
  puts "Wrong environment argument. Should be 'test', 'local', 'preview', 'beta', or 'live'."
  exit
end

# Catch all exceptions and throw them to hoptoad.
begin
  require File.join("lib", "odbc_spree")
  include Spree::ODBC

  start_time = Time.now

  @rm = RM.new(env, bootstrap)
  @rm.log.debug("\n\n -=- MYOB Database Synchronization Script started. -=- \n")

  # ------ Begin Code Execution -------

  # Cache valid google spreadsheet products
  @rm.cache_valid_products

  # Connect to ODBC data source and fetch data
  @rm.connect
  @rm.fetch_current_data
  @rm.fetch_old_data

  # MYOB contains no information about images. We need to inject the image data (+ timestamp) into a mock column.
  # inject_image_data(@stock_records_current)

  # --------------------------------------------------------------------
  #                   Departments and Categories
  # --------------------------------------------------------------------

  category_changes = {}
  [:dept, :cat1].each do |c|
    table = c == :dept ? "Department" : "Category"
    @rm.log.debug("== Scanning for #{table} changes ...")

    category_changes[c], vcc = @rm.compare_tables(@rm.categories_current[c],
                                                  @rm.categories_old[c])

    if category_changes[c].size == 0
      @rm.log.debug("===== Found no changes in #{table} table.")
    else
      @rm.log.debug(%Q":: Some #{table} records have been changed:
  ===== #{vcc[:update] } updated item(s)
  ===== #{vcc[:new] } new item(s)
  ===== #{vcc[:delete] } deleted item(s)")
    end
  end


  errors_for_email = {}
  # If there were any category changes, push them to Spree.
  category_changes[:dept].each { |id, action|
    @rm.process_department_change(id, action, errors_for_email)
  }
  # Fetch all taxonomies from Spree.
  @rm.get_spree_taxonomies
  # If there were any category changes, push them to Spree.
  category_changes[:cat1].each { |id, action|
    @rm.process_category_change(id, action, errors_for_email)
  }

  # Save the categories data.
  @rm.save_categories_data_to_files

  # Fire off an error_email if there are any errors.
  send_category_hoptoad_notification(errors_for_email) if errors_for_email != {}


  # --------------------------------------------------------------------
  #                             Stock
  # --------------------------------------------------------------------
  @rm.log.debug("== Scanning for Stock changes ...")

  stock_changes, vcc = @rm.compare_tables(@rm.md5_hash_current,
                                          @rm.md5_hash_old)

  if stock_changes.size == 0
    @rm.log.debug("===== Found no changes in Stock table.")
  else
    @rm.log.debug(%Q":: Some Stock records have been changed:
  ===== #{vcc[:update] } updated item(s)
  ===== #{vcc[:new] } new item(s)
  ===== #{vcc[:delete] } deleted item(s)")
  end


  action_count = {:new => 0,
                  :update => 0,
                  :delete => 0,
                  :image => 0,
                  :ignore => 0,
                  :ignore_image => 0,
                  :ignore_valid => 0,
                  :error => 0}

  @rm.log.debug("== Fetching all taxons from Spree...")
  @rm.get_spree_taxons

  depts = {}
  taxonomys = {}
  taxons = {}

  @rm.log.debug("== Processing Stock record changes...") unless stock_changes.empty?
  # If there were any record changes, push them to Spree.
  stock_changes.each do |stock_id, stock_action|
    @rm.process_stock_change(stock_id, stock_action, action_count)
  end


  # If there have been any changes, pull translations from google spreadsheet.
  if action_count[:update] > 0 or action_count[:new] > 0
    # Sends a get request to the server,
    # to trigger the 'translate products' method.
    # (Pulls translations from google spreadsheet.)
    ProductSync.find("translate") rescue nil
  end


  # Remove ignored stock from current records and md5 hashes.
  @rm.remove_ignored_stock

  # Update the saved stock record files to current data.
  @rm.log.debug("Saving updated records and MD5 hashes to disk...")
  @rm.save_stock_data_to_files


  report = %Q"

  :: MYOB Database Synchronization Script has finished.
    -- Completed in #{Time.now - start_time} seconds.
                 -- (#{'%.3f' % ((Time.now - start_time) / 60)} minutes.)
       - Added #{action_count[:new]} product(s) to the web-store.
          - Ignored #{action_count[:ignore_image]} product(s) that did not have images to upload.
          - Ignored #{action_count[:ignore_valid]} product(s) that were not part of the 'proofed descriptions' list.
          - There were #{action_count[:new] + action_count[:ignore_image] + action_count[:ignore_valid]} product(s) available for the webstore.
       - Updated #{action_count[:update]} product(s) in the web-store.
       - Deleted #{action_count[:delete]} product(s) from the web-store.
       - Uploaded #{action_count[:image]} image(s) to products in the web-store.
       - Ignored #{action_count[:ignore]} product(s) that were not web-store related.
       - There were #{action_count[:error]} total errors.
  "

  @rm.log.debug(report)

  # Send an hoptoad notification if errors were encountered.
  @rm.send_hoptoad_notification(report) if action_count[:error] > 0

rescue Exception => ex
  require 'toadhopper'
  config = YAML.load_file(File.join("config", "config_#{env}.yml"))
  Toadhopper.new(config["hoptoad_api_key"], :notify_host => (config["hoptoad_host"])).post!(ex)
end

