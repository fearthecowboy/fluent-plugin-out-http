class Fluent::HTTPOutput < Fluent::Output
  Fluent::Plugin.register_output('http_streaming', self)

  def initialize
    super
    require 'net/http'
    require 'uri'
    require 'yajl'
    require "base64"    
  end

  # Endpoint URL ex. localhost.local/api/
  config_param :endpoint_url, :string

  # HTTP method
  config_param :http_method, :string, :default => :post
  
  # idle_flush (seconds)
  config_param :idle_flush, :integer, :default => 15
  
  # form | json | msgpack
  config_param :serializer, :string, :default => :msgpack

  # Simple rate limiting: ignore any records within `rate_limit_msec`
  # since the last one.
  config_param :rate_limit_msec, :integer, :default => 0

  # Raise errors that were rescued during HTTP requests?
  config_param :raise_on_error, :bool, :default => true

  # nil | 'none' | 'basic'
  config_param :authentication, :string, :default => nil 
  config_param :username, :string, :default => ''
  config_param :password, :string, :default => ''

  config_param :use_streaming, :bool, :default => false

  def configure(conf)
    super

    serializers = [:json, :form, :msgpack]
    @serializer = if serializers.include? @serializer.intern
                    @serializer.intern
                  else
                    :form
                  end

    http_methods = [:get, :put, :post, :delete]
    @http_method = if http_methods.include? @http_method.intern
                    @http_method.intern
                  else
                    :post
                  end

    @auth = case @authentication
            when 'basic' then :basic
            else
              :none
            end
  end

  def start
    super
    @connection_verified = false
    if @use_streaming 
      flush
      @running = true
      Thread.new { idle }
    end
  
  end

  def idle
    while @running 
        if not @connection_verified or (not @last_request_time.nil? and (@last_request_time + @idle_flush) < Time.now.to_f)
            flush
            @last_request_time = nil
        end
        sleep @idle_flush
    end 
  end

  def shutdown
    super
    @running = false
    disconnect_streaming
  end

  def disconnect_streaming
    if @use_streaming
        if not @write.nil? and not @write.closed?
            old_write = @write
            @write = nil
            old_write.close 
        end
    end
  end 

  def connect_streaming
    if @use_streaming
        if not @connection_verified
          test_connection
        end
      
        if @connection_verified
            # the server seems to respond, let's start a stream.
            @read, @write = IO.pipe
        
            uri = URI.parse(@endpoint_url)
            req = Net::HTTP.const_get(@http_method.to_s.capitalize).new(uri.path)
            req['Transfer-Encoding'] = 'chunked'
            req['Content-Type'] = 'application/x-msgpack'
            
            req.body_stream = @read
            Thread.new { http = start_request(req, uri) }
        end
    end
  end 

  def test_connection
    begin
      uri = URI.parse( @endpoint_url )
      
      # attempt a quick connection to the server.
      http = Net::HTTP.new( uri.host, uri.port )
      http.open_timeout = 5
      http.start {
          response = http.head('/')
          http.finish
      }
    rescue => e # rescue all StandardErrors
       @connection_verified = false
       $stdout << "DEBUG: Connection to server not available."<< "\n"
    else
       @connection_verified = true
       $stdout << "DEBUG: Connection to server verified."<< "\n"
    end
  end

  def flush 
      if @use_streaming
        if not @write.nil? and not @write.closed?
            old_write = @write
            @last_request_time = nil
        end
        
        # create a new connection 
        connect_streaming
        
        # close the old connection (will finish writing data)
        if not old_write.nil? and not old_write.closed?       
            old_write.close 
        end
    end
  end 
  
  def format_url(tag, time, record)
    @endpoint_url
  end

  def set_body(req, tag, time, record)
    if @serializer == :json
      set_json_body(req, record)
    else
        if @serializer == :msgpack
            set_msgpack_body(req, record)
        else
            req.set_form_data(record)
        end
    end
    req
  end

  def set_header(req, tag, time, record)
    req
  end

  def set_json_body(req, data)
    req.body = Yajl.dump(data)
    req['Content-Type'] = 'application/json'
  end

  def set_msgpack_body(req, data)
    req.body = data.to_msgpack
    req['Content-Type'] = 'application/x-msgpack'
  end

  def create_request(tag, time, record)
    url = format_url(tag, time, record)
    uri = URI.parse(url)
    req = Net::HTTP.const_get(@http_method.to_s.capitalize).new(uri.path)
    set_body(req, tag, time, record)
    set_header(req, tag, time, record)
    return req, uri
  end


  def start_request(req, uri)    
    res = nil

    begin
      if @auth and @auth == :basic
        req.basic_auth(@username, @password)
      end
     
      res = Net::HTTP.new(uri.host, uri.port).start {|http|  http.request(req) }
    rescue => e # rescue all StandardErrors
      # server didn't respond
      $log.warn "Net::HTTP.#{req.method.capitalize} raises exception: #{e.class}, '#{e.message}'"
      
      # make the next connection do a verify first.
      @connection_verified = false
      
      # try to open a new connection
      flush
      
      raise e if @raise_on_error
     else
       unless res and res.is_a?(Net::HTTPSuccess)
          res_summary = if res
                           "#{res.code} #{res.message} #{res.body}"
                        else
                           "res=nil"
                        end
          $log.warn "failed to #{req.method} #{uri} (#{res_summary})"
       end #end unless
    end # end begin
  end # end start_request

  def handle_record(tag, time, record)
    is_rate_limited = (@rate_limit_msec != 0 and not @last_request_time.nil?)
    if is_rate_limited and ((Time.now.to_f - @last_request_time) * 1000.0 < @rate_limit_msec)
      $log.info('Dropped request due to rate limiting')
      return
    end
    @last_request_time = Time.now.to_f
     
    if @use_streaming
        
        packedMessage =  ["source machine", tag ,time, record]
        
        # Proof-of-concept, work around idiotic bugs in v6 of messagepack-java 
        # (where it encodes binary arrays as strings.)
        # We're smuggling in the data as base64 and then quickly unpacking it 
        # here.
        
        if record.is_a?(Array)
            # did this come from 
        end
        
        if not record.is_a?(Array) and not record["dataBase64"].nil? 
            d = record["dataBase64"]
            bin = Base64.decode64( d )
            record.delete("dataBase64")
            record["data"] = d
           # $stdout << "RECORD: #{record["data"].class} \n" 
           # $stdout << "RECORD: #{record["data"]} \n" 
           # $stdout << "RECORD: #{record} \n" 
        end 
        
        if @write.nil?
            $log.info('Droppping message -- connection not available')
            @last_request_time = nil
        else
            @write.write packedMessage.to_msgpack
        end
    else 
        req, uri = create_request(tag, time, record)
        http = start_request(req, uri)
    end
  end

  def emit(tag, es, chain)
    es.each do |time, record|
      handle_record(tag, time, record)
    end
    chain.next
  end
end
