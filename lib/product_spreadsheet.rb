class ProductSpreadsheet

  def initialize
    @table = "products"

    @locales = ["en-US", "zh-TW", "zh-CN"]

    @initial_offset = 1 # data starts at row 1 on sheets

    @column_headings = ["Product Barcode (SKU)",
                        "Product Name",
                        "Product Description"]
    @columns = [:sku, :name, :description]

    @google_worksheet_map = %w(
      instructions products taxonomies taxons
      shipping producers
    )

    google_conf = YAML.load_file(File.join(File.dirname(__FILE__), '..', 'config', 'google_docs_translations.yml'))
    @google_username = google_conf["username"]
    @google_password = google_conf["password"]
    @google_spreadsheet_url = google_conf["spreadsheet_url"]
  end

  # -------- Google docs Spreadsheet API ---------

  def valid_products
  
    valid_arr = []

    puts "== Logging in to google docs with user: '#{@google_username}'..."
    session = GoogleSpreadsheet.login(@google_username, @google_password)

    puts "===== Success."

    spreadsheet = session.spreadsheet_by_url(@google_spreadsheet_url)

    sheet = spreadsheet.worksheets[
            @google_worksheet_map.index(@table)]

    puts "== Fetching valid products..."

    # First column heading is the main 'key' or ID
    col_key = @columns.shift

    row = @initial_offset+1
    begin
      # Initialize row hash with hashes for each locale
      row_hash = @locales.inject({}){|r,x|
                               r.update(x => {})}
      row_hash[:id] = sheet[row, 1]

      valid = true
      @columns.each_with_index do |column, col_i|
        @locales.each_with_index do |locale, loc_i|
          col_pos = (col_i * @locales.size) + loc_i + 2
          row_hash[locale][column] = sheet[row, col_pos]
          valid = false if row_hash[locale][column].blank?
        end
      end

      valid_arr << row_hash[:id] if valid
      

      row += 1

    end while !sheet[row, 1].blank?

    puts "===== Found #{row - @initial_offset} row(s) of valid product translations."

    return valid_arr
  end

end
