require 'net/https'

Toadhopper.class_eval do

  def deploy!(options={})
    params = {}
    params['api_key'] = @api_key
    params['deploy[rails_env]'] = options[:framework_env] || 'development'
    params['deploy[local_username]'] = options[:username] || %x(whoami).strip
    params['deploy[scm_repository]'] = options[:scm_repository]
    params['deploy[scm_revision]'] = options[:scm_revision]

    url = URI.parse(@deploy_url)
    http = Net::HTTP.new(url.host, url.port)
    if url.scheme == "https"
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    headers = {'Content-Type'=> 'application/x-www-form-urlencoded'}
    resp, data = http.post(url.path, params, headers)

    parse_response(resp)
  end


  private
  def post_document(document, headers={})
    uri = URI.parse(@error_url)

    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == "https"
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    http.read_timeout = 5 # seconds
    http.open_timeout = 2 # seconds
    begin
      response = http.post uri.path,
                           document,
                           {'Content-type' => 'text/xml', 'Accept' => 'text/xml, application/xml'}.merge(headers)
      parse_response(response)
    rescue TimeoutError => e
      Response.new(500, '', ['Timeout error'])
    end
  end
end

