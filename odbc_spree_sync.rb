#!/usr/bin/env ruby

require File.join("lib", "odbc_spree")
include Spree::ODBC

env, bootstrap = ARGV[0], ARGV[1]

if not ["test", "local", "preview", "beta", "live"].include? env
  puts "Wrong environment argument. Should be 'test', 'local', 'preview', 'beta', or 'live'."
  exit
end

start_time = Time.now

@rm = RM.new(env, bootstrap)
@rm.log.debug("\n\n -=- MYOB Database Synchronization Script started. -=- \n")

# ------ Begin Code Execution -------

@rm.connect

@rm.fetch_current_data
@rm.fetch_old_data

# MYOB contains no information about images. We need to inject the image data (+ timestamp) into a mock column.
# inject_image_data(@stock_records_current)

# --------------------------------------------------------------------
#                   Departments and Categories
# --------------------------------------------------------------------
@rm.log.debug("== Scanning for Department and Category changes ...")


category_changes = {}
[:dept, :cat1].each do |c|
  category_changes[c] = @rm.compare_tables(@rm.categories_current[c],
                                           @rm.categories_old[c])
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


# Sends a get request to the server,
# to trigger the 'translate taxons' method.
######### TaxonSync.find("translate")
######### (our translations are all handled by google docs now)

# Save the categories data.
@rm.save_categories_data_to_files

# Fire off an error_email if there are any errors.
send_error_email(errors_for_email) if errors_for_email != {}


# --------------------------------------------------------------------
#                             Stock
# --------------------------------------------------------------------
@rm.log.debug("== Scanning for Stock changes ...")

stock_changes = @rm.compare_tables(@rm.md5_hash_current,
                                   @rm.md5_hash_old)

action_count = {:new => 0,
                :update => 0,
                :delete => 0,
                :image => 0,
                :ignore => 0,
                :ignore_image => 0,
                :ignore_valid => 0,
                :error => 0}

# Fetch all taxons from Spree.
@rm.get_spree_taxons

depts = {}
taxonomys = {}
taxons = {}

# If there were any record changes, push them to Spree.
stock_changes.each do |stock_id, stock_action|
  @rm.process_stock_change(stock_id, stock_action, action_count)
end

# Update the saved stock record files to current data.
@rm.log.debug("Saving updated records and MD5 hashes to disk...")
@rm.save_stock_data_to_files


@rm.log.debug(%Q"

:: MYOB Database Synchronization Script has finished.
  -- Completed in #{Time.now - start_time} seconds.
               -- (#{'%.3f' % ((Time.now - start_time) / 60)} minutes.)
     - Added #{action_count[:new]} product(s) to the web-store.
        - Ignored #{action_count[:ignore_image]} product(s) that did not have images to upload.
        - Ignored #{action_count[:ignore_valid]} product(s) that were not part of the 'proofed descriptions' list.
        - There were #{action_count[:new] + action_count[:ignore_image]} product(s) available for the webstore.
     - Updated #{action_count[:update]} product(s) in the web-store.
     - Deleted #{action_count[:delete]} product(s) from the web-store.
     - Uploaded #{action_count[:image]} image(s) to products in the web-store.
     - Ignored #{action_count[:ignore]} product(s) that were not web-store related.
     - There were #{action_count[:error]} total errors.
")

