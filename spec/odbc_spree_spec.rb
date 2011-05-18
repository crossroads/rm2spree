# How to run this RSpec test suite:
# -> Open a cmd prompt
# -> Change directory to the script directory
# -> Run the following command:
#
#       spec -O spec/spec.opts odbc_spree_functions_spec.rb
ARGV[0] = "local"
require File.join(File.dirname(__FILE__), 'spec_helper.rb')

include Spree::ODBC

describe Spree::ODBC::RM do
  before :all do
    stub_dbi
    @rm = RM.new("test")
  end

  describe "Initializing Config" do
    it "should be able to append '/' to the spree baseurl if not there." do
      # config_test.yml contains: "http://localhost:3000"
      @rm.spree_baseurl.should == "http://localhost:3000/"
    end
  end

  describe "File Operations (Saving YAML Data, etc.)" do
    before :each do  # stub out file class so it doesnt read or write.
      File.stub!(:exist?).and_return(false)
      file_object = stub(:write => true)
      File.stub!(:open).and_return(file_object)
    end

    it "should be able to find that a file doesnt exist and create the file with the given data." do
      filename = "foo.bar"
      sample_data = "this is some sample data to write if file doesnt exist."
      @rm.load_file_with_defaults(filename, {}).should == {}
      @rm.load_file_with_defaults(filename, true).should == true
    end
  end

  describe "MYOB Database ODBC Connection - Stock Records" do
    it "should be able to fetch all stock records from the ODBC database connection" do
      @rm.fetch_stock_records[1].should == sample_stock_record[1]
    end
  end


  describe "Categories" do
    it "should be able to fetch all categories from the ODBC database connection" do
      @rm.fetch_categories.should == sample_categories
    end

    it "should be able to fetch all categorised_values records from the ODBC database connection" do
      @rm.fetch_categorised_values.should == sample_categorised_values
    end

    it "should be able to fetch all departments from the ODBC database connection" do
      @rm.fetch_departments.should == sample_department_values
    end

    it "should be able to find the category ids for a given stock_id" do
      stock_id = 1
      @rm.find_category_by_stockid(stock_id).should == {:dept_id => 1, :sub_cat => 50}
    end

    it "should be able to find the details and hierarchy for a given catvalue_id" do
      catvalue_id = 10
      sample_categories_data = {:cat1 => sample_categories, :dept => sample_department_values}
      @rm.find_category_details_by_catvalue_id(
        catvalue_id,
        sample_categories_data,
        sample_categorised_values).should == {:sub_cat => 10,
                                              :cat_name => "DECOR",
                                              :dept_details =>
                                                {1 => "ACCESSORY",
                                                 3 => "CLOTHING"}}
    end
  end

  describe "Emails" do
    before :each do
      Net::SMTP.stub!(:new).and_return(MockSMTP.new)
    end

    it "should send hoptoad notification about deleted categories." do
      error_message = {:subject => "Test email", 1 => {:message => "A category has been deleted. It might need to be removed from the webstore, and corresponding products might need to be updated.",
                 :previous_state => "Test Product",
                 :new_state => "## DELETED"}}
      msg = @rm.send_category_hoptoad_notification(error_message)
      msg.include?('A category has been deleted.').should == true
      msg.include?('Test Product').should == true
      msg.include?('## DELETED').should == true
    end

    it "should send hoptoad notification with error summary." do
      msg = @rm.send_hoptoad_notification(":: MYOB Database Synchronization Script has finished.")
      msg.include?('MYOB Database Synchronization Script has finished').should == true
    end
  end

  describe "MD5 Hashes" do
    it "should be able to find MD5 hashes from stock records." do
      @rm.get_md5_hashes(sample_stock_record)[1].should_not == nil
    end

    it "should be able to find updated records based on md5 hash changes" do
      md5hash_new = {1 => "0d3eb35b9dd03df47138d78bf322e05f"}
      md5hash_old = {1 => "[CHANGED]0d3eb35b9dd03df47138d78bf322e05f"}
      @rm.compare_tables(md5hash_new, md5hash_old)[0][1].should == :update
    end

    it "should be able to find new records based on md5 hash changes" do
      md5hash_new = {1 => "0d3eb35b9dd03df47138d78bf322e05f"}
      md5hash_old = {}
      @rm.compare_tables(md5hash_new, md5hash_old)[0][1].should == :new
    end

    it "should be able to find deleted records based on md5 hash changes" do
      md5hash_new = {}
      md5hash_old = {1 => "0d3eb35b9dd03df47138d78bf322e05f"}
      @rm.compare_tables(md5hash_new, md5hash_old)[0][1].should == :delete
    end
  end

  describe "Product data mapping" do
    it "should use the net quantity of a product" do
      stock = sample_stock_record.dup
      stock[1]["quantity"] = 23
      stock[1]["layby_qty"] = 12
      @rm.get_product_data(1, stock)["on_hand"].should == 23
    end
  end

  describe "Spree Active Resource Connection" do
    before :all do   # stub out the product and TaxonSync classes so they dont actually call the spree API
      Taxon = stub("Taxon")
      @rm.categories_current = sample_full_categories
    end

    before :each do
      Product.stub!(:attributes).and_return(sample_spree_record)
      Product.stub!(:valid?).and_return(true)
      Product.stub!(:deleted_at=).and_return(Time.now)
      Product.stub!(:save).and_return(true)
      Product.stub!(:permalink).and_return("test_product")

      Taxon.stub!(:save).and_return(true)
      ProductSync.stub!(:find).and_return([Product])
      ProductSync.stub!(:new).and_return(Product)
      TaxonSync.stub!(:find).and_return(true)
      TaxonSync.stub!(:new).and_return(Taxon)
      TaxonomySync.stub!(:find).and_return(true)
      TaxonomySync.stub!(:new).and_return(Taxon)
    end

    it "should be able to find and return all products currently in the Spree store" do
      ProductSync.find(:all).should == [Product]
    end

    it "should be able to find a product in the Spree store by 'stock_id'" do
      stock_id = 1
      product = ProductSync.find_by_stock_id(stock_id)
      product.should == Product
    end

    it "should be able to add a new product to the Spree database" do
      stock_id = 1
      sample_product_data = {"name" => "Test Product", "description" => "Test Description", "taxon_id" => "123"}
      @rm.add_spree_product(sample_product_data).should_not == false
    end

    it "should be able to update a product in the Spree database" do
      ProductSync.should_receive(:find_by_stock_id).with(1).and_return(Product)

      Product.stub!(:attributes).and_return(sample_spree_record)
      stub!(:upload_image).and_return(true)
      @rm.spree_taxons = []
      @rm.spree_taxonomies = []
      @rm.update_spree_product(1, sample_stock_record, sample_stock_record).should_not == false
    end

    it "should not include name and description when updating a product" do
      update_data = @rm.get_product_data_for_update(1, sample_stock_record)
      update_data["name"].should == nil
      update_data["description"].should == nil
    end

    it "should be able to delete a product from the Spree database" do
      stock_id = 1
      @rm.delete_spree_product(stock_id).should_not == false
    end

    it "should be able to find and return all taxons currently in the Spree store" do
      TaxonSync.find(:all).should == true
    end

    it "should be able to find and return all taxonomies currently in the Spree store" do
      TaxonomySync.find(:all).should == true
    end

    it "should be able to add new taxons and taxonomies to Spree" do
      sample_taxon_data = {"name" => "Test Taxon"}
      @rm.add_spree_category(sample_taxon_data, :taxon).should_not == false
      @rm.add_spree_category(sample_taxon_data, :taxonomy).should_not == false
    end

    it "should be able to upload a valid new image to a Spree product in the database" do
      file_path = "spec/test_image.jpg"
      # generate a random 512KB image file in /tmp
      create_dummy_image(file_path, 0.5)
      @rm.upload_image(file_path, "TEST PRODUCT").should == true
      delete_dummy_image(file_path)
    end

    it "should not be able to upload an image that is larger than 1MB" do
      file_path = "spec/test_image.jpg"
      # generate a random 1.5MB image file in /tmp
      create_dummy_image(file_path, 1.5)
      @rm.upload_image(file_path, "TEST PRODUCT").should == false
      delete_dummy_image(file_path)
    end
  end

  describe "Stock Actions" do
    it "should be able to logically handle different cases when the web_store field changes" do
      #evaluate_stock_action_with_webstore(stock_action, web_store_old, web_store_current)
      @rm.evaluate_stock_action_with_webstore(:update, "yes", "yes").should == :update
      @rm.evaluate_stock_action_with_webstore(:update, "yes", "no").should == :delete
      @rm.evaluate_stock_action_with_webstore(:update, "no", "yes").should == :new
      @rm.evaluate_stock_action_with_webstore(:delete, "yes", "yes").should == :delete
      @rm.evaluate_stock_action_with_webstore(:delete, "yes", "no").should == :delete
      @rm.evaluate_stock_action_with_webstore(:delete, "no", "yes").should == nil
      @rm.evaluate_stock_action_with_webstore(:new, "yes", "yes").should == :new
      @rm.evaluate_stock_action_with_webstore(:new, "yes", "no").should == nil
      @rm.evaluate_stock_action_with_webstore(:new, "no", "yes").should == :new
    end
  end

  describe "Saving stored data" do
    it "should be able to remove ignored products before saving stored data" do
      records = {}
      (1..10).each do |i|
        records[i] = sample_stock_record[1]
      end

      @rm.stock_records_current = records
      @rm.md5_hash_current = {}
      @rm.ignored_stock = [1, 5, 4]
      @rm.remove_ignored_stock

      [1,5,4].each do |i|
        @rm.stock_records_current[i].should == nil
      end
      [2,3,6,7,8,9,10].each do |i|
        @rm.stock_records_current[i].should_not == nil
      end
    end
  end

end

