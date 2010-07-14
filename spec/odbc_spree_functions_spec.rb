# How to run this RSpec test suite:
# -> Open a cmd prompt
# -> Change directory to the script directory
# -> Run the following command:
#
#       spec -O spec/spec.opts odbc_spree_functions_spec.rb
ARGV[0] = "local"
require File.join(File.dirname(__FILE__), 'spec_helper.rb')

describe "File Operations (Saving YAML Data, etc.)" do
  before :each do  # stub out file class so it doesnt read or write.
    File.stub!(:exist?).and_return(false)
    file_object = stub(:write => true)
    File.stub!(:open).and_return(file_object)
  end
  
  it "should be able to find that a file doesnt exist and create the file with the given data." do
    filename = "foo.bar"
    sample_data = "this is some sample data to write if file doesnt exist."
    write_or_load_data_if_file_exists(filename,  sample_data, {}).should == {}
    write_or_load_data_if_file_exists(filename,  sample_data, true).should == sample_data
  end
end


describe "MYOB Database ODBC Connection - Stock Records" do
  before :each do   # stub out the product and Taxon_Sync classes so they dont actually call the spree API
    DBI.stub!(:connect).and_return(MockODBCConnection.new)
  end
  
  it "should be able to fetch all stock records from the ODBC database connection" do
    fetch_stock_records[1].should == sample_stock_record[1]
  end 
end


describe "Categories" do
  before :each do   # stub out the ODBC connection so it returns certain sample data-sets for certain SQL queries.
    DBI.stub!(:connect).and_return(MockODBCConnection.new)
  end
  
  it "should be able to fetch all categories from the ODBC database connection" do
    fetch_categories.should == sample_categories
  end
  
  it "should be able to fetch all categorised_values records from the ODBC database connection" do
    fetch_categorised_values.should == sample_categorised_values
  end 
  
  it "should be able to fetch all departments from the ODBC database connection" do
    fetch_departments.should == sample_department_values
  end
  
  it "should be able to find the category ids for a given stock_id" do
    stock_id = 1
    find_category_by_stockid(stock_id).should == {:dept_id => 1, :sub_cat => 50}
  end

  it "should be able to find the details and hierarchy for a given catvalue_id" do
    catvalue_id = 10
    sample_categories_data = {:cat2 => sample_categories, :dept => sample_department_values}
    find_category_details_by_catvalue_id(catvalue_id, sample_categories_data, sample_categorised_values).should == {:sub_cat=>10, :cat_name=>"DECOR", :dept_details=>{1 => "ACCESSORY", 3=>"CLOTHING"}}
  end
end

describe "Emails" do
  before :each do
    Net::SMTP.stub!(:new).and_return(MockSMTP.new)
  end
  
  it "should notify an administrator by email about deleted categories." do
    errors_for_email = {:subject => "Test email", 1 => {:message => "A category has been deleted. It might need to be removed from the webstore, and corresponding products might need to be updated.",
               :previous_state => "Test Product",
               :new_state => "## DELETED"}}
    email_body = send_error_email(errors_for_email)
    email_body.include?('A category has been deleted.').should == true
    email_body.include?('Test Product').should == true
    email_body.include?('## DELETED').should == true
  end
end

describe "MD5 Hashes" do
  it "should be able to find MD5 hashes from stock records." do
    get_md5_hashes(sample_stock_record)[1].should_not == nil
  end
  
  it "should be able to find updated records based on md5 hash changes" do
    md5hash_new = {1 => "0d3eb35b9dd03df47138d78bf322e05f"}
    md5hash_old = {1 => "[CHANGED]0d3eb35b9dd03df47138d78bf322e05f"}
    compare_tables(md5hash_new, md5hash_old)[1].should == :update
  end
  
  it "should be able to find new records based on md5 hash changes" do
    md5hash_new = {1 => "0d3eb35b9dd03df47138d78bf322e05f"}
    md5hash_old = {}
    compare_tables(md5hash_new, md5hash_old)[1].should == :new
  end
  
  it "should be able to find deleted records based on md5 hash changes" do
    md5hash_new = {}
    md5hash_old = {1 => "0d3eb35b9dd03df47138d78bf322e05f"}
    compare_tables(md5hash_new, md5hash_old)[1].should == :delete
  end
end

describe "Spree Active Resource Connection" do
  before :all do   # stub out the product and Taxon_Sync classes so they dont actually call the spree API
    Product = stub("Product")
    Product.stubs(:attributes).returns(sample_spree_record)
    Product.stubs(:valid?).returns(true)
    Product.stubs(:deleted_at=).returns(Time.now)
    Product.stubs(:save).returns(true)
    Product.stubs(:permalink).returns("test_product")
    
    Taxon = stub("Taxon")
    Taxon.stubs(:save).returns(true)
    
  end
  
  before :each do
    Product_Sync.stub!(:find).and_return([Product])
    Product_Sync.stub!(:new).and_return(Product)
    Taxon_Sync.stub!(:find).and_return(true)
    Taxon_Sync.stub!(:new).and_return(Taxon)
    Taxonomy_Sync.stub!(:find).and_return(true)
    Taxonomy_Sync.stub!(:new).and_return(Taxon)
  end
  
  it "should be able to find and return all products currently in the Spree store" do
    Product_Sync.find(:all).should == [Product]
  end
  
  it "should be able to find a product in the Spree store by 'stock_id'" do
    stock_id = 1
    product = Product_Sync.find_by_stock_id(stock_id)
    product.should == Product
  end
  
  it "should be able to add a new product to the Spree database" do
    stock_id = 1
    sample_product_data = {"name" => "Test Product", "description" => "Test Description"}
    add_spree_product(sample_product_data).should_not == false
  end
  
  it "should be able to update a product in the Spree database" do
    Product_Sync.should_receive(:find_by_stock_id).with(1).and_return(mock(Product))
    stub!(:upload_image).and_return(true)
    @spree_taxons = []
    @spree_taxonomies = []
    stock_id = 1
    update_spree_product(stock_id, sample_stock_record, sample_stock_record).should_not == false
  end
  
  it "should be able to delete a product from the Spree database" do
    stock_id = 1
    delete_spree_product(stock_id).should_not == false
  end
    
  it "should be able to find and return all taxons currently in the Spree store" do
    Taxon_Sync.find(:all).should == true
  end
  
  it "should be able to find and return all taxonomies currently in the Spree store" do
    Taxonomy_Sync.find(:all).should == true
  end
  
  it "should be able to add new taxons and taxonomies to Spree" do
    sample_taxon_data = {"name" => "Test Taxon"}
    add_spree_category(sample_taxon_data, :taxon).should_not == false
    add_spree_category(sample_taxon_data, :taxonomy).should_not == false
  end
  
  it "should be able to upload a new image to a Spree product in the database" do
    upload_image("foo.jpg", "TEST PRODUCT").should == true
  end
end

describe "Stock Actions" do
  it "should be able to logically handle different cases when the web_store field changes" do
    #evaluate_stock_action_with_webstore(stock_action, web_store_old, web_store_current)
    evaluate_stock_action_with_webstore(:update, "yes", "yes").should == :update
    evaluate_stock_action_with_webstore(:update, "yes", "no").should == :delete
    evaluate_stock_action_with_webstore(:update, "no", "yes").should == :new
    evaluate_stock_action_with_webstore(:delete, "yes", "yes").should == :delete
    evaluate_stock_action_with_webstore(:delete, "yes", "no").should == :delete
    evaluate_stock_action_with_webstore(:delete, "no", "yes").should == nil
    evaluate_stock_action_with_webstore(:new, "yes", "yes").should == :new
    evaluate_stock_action_with_webstore(:new, "yes", "no").should == nil
    evaluate_stock_action_with_webstore(:new, "no", "yes").should == :new
  end
end
