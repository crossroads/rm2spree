require 'net/http'
require 'net/https'

class Multipart

  def initialize(file_names)
    @file_names = file_names
  end

  def post(to_url, content_type, user, password)
    boundary = '----RubyMultipartClient' + rand(1000000).to_s + 'ZZZZZ'

    parts = []
    streams = []

    @file_names.each do |param_name, filepath|
      #pos = filepath.rindex("\\")
      filename = filepath.split("\\").last
      #filename = filepath[pos + 1, filepath.length - pos]
      parts << StringPart.new( "--" + boundary + "\r\n" +
      "Content-Disposition: form-data; name=\"" + param_name.to_s + "\"; filename=\"" + filename + "\"\r\n" +
      "Content-Type: #{content_type}\r\n\r\n")
      stream = File.open(filepath, "rb")
      streams << stream
      parts << StreamPart.new(stream, File.size(filepath))
    end
    parts << StringPart.new( "\r\n--" + boundary + "--\r\n" )

    #parts << StringPart.new( "--" + boundary + "\r\n" +
    #  "Content-Disposition: form-data; name=\"authenticity_token\"; value=\"" + auth_token + "\"\r\n")
    #parts << StringPart.new( "\r\n--" + boundary + "--\r\n" )

    post_stream = MultipartStream.new( parts )

    url = URI.parse( to_url )
    req = Net::HTTP::Post.new(url.path)
    req.content_length = post_stream.size
    req.content_type = 'multipart/form-data; boundary=' + boundary
    req.body_stream = post_stream

    req.basic_auth user, password if user  && password
    net_http = Net::HTTP.new(url.host, url.port)

    if url.scheme == "https"
      net_http.use_ssl = true
      # Make ssl timeout reasonable for large image uploads
      net_http.timeout = 75
    end

    res = net_http.start {|http| http.request(req) }

    streams.each do |stream|
      stream.close();
    end

    res
  end

end

class StreamPart
  def initialize( stream, size )
    @stream, @size = stream, size
  end

  def size
    @size
  end

  def read( offset, how_much )
    @stream.read( how_much )
  end
end

class StringPart
  def initialize( str )
    @str = str
  end

  def size
    @str.length
  end

  def read( offset, how_much )
    @str[offset, how_much]
  end
end

class MultipartStream
  def initialize( parts )
    @parts = parts
    @part_no = 0;
    @part_offset = 0;
  end

  def size
    total = 0
    @parts.each do |part|
      total += part.size
    end
    total
  end

  def read( how_much )

    if @part_no >= @parts.size
      return nil;
    end

    how_much_current_part = @parts[@part_no].size - @part_offset

    how_much_current_part = if how_much_current_part > how_much
      how_much
    else
      how_much_current_part
    end

    how_much_next_part = how_much - how_much_current_part

    current_part = @parts[@part_no].read(@part_offset, how_much_current_part )

    if how_much_next_part > 0
      @part_no += 1
      @part_offset = 0
      next_part = read(how_much_next_part)
      current_part + if next_part
        next_part
      else
        ''
      end
    else
      @part_offset += how_much_current_part
      current_part
    end
  end
end

