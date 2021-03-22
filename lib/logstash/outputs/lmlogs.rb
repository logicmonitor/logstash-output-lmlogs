# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "logstash/json"
require 'uri'
require 'json'
require 'date'
require 'base64'
require 'openssl'
require 'manticore'

# An example output that does nothing.
class LogStash::Outputs::LMLogs < LogStash::Outputs::Base
  class InvalidHTTPConfigError < StandardError; end

  concurrency :shared
  config_name "lmlogs"

  # Event batch size to send to LM Logs. Increasing the batch size can increase throughput by reducing HTTP overhead
  config :batch_size, :validate => :number, :default => 100

  # Key that will be used by the plugin as the log message
  config :message_key, :validate => :string, :default => "message"

  # Key that will be used by the plugin as the system key
  config :property_key, :validate => :string, :default => "host"

  # Key that will be used by LM to match resource based on property
  config :lm_property, :validate => :string, :default => "system.hostname"

  # Keep logstash timestamp
  config :keep_timestamp, :validate => :boolean, :default => true
  
  # Use a configured message key for timestamp values
  # Valid timestamp formats are ISO8601 strings or epoch in seconds, milliseconds or nanoseconds
  config :timestamp_is_key, :validate => :boolean, :default => false
  config :timestamp_key, :validate => :string, :default => "logtimestamp"

  # Display debug logs
  config :debug, :validate => :boolean, :default => false

  # Timeout (in seconds) for the entire request
  config :request_timeout, :validate => :number, :default => 60

  # Timeout (in seconds) to wait for data on the socket. Default is `10s`
  config :socket_timeout, :validate => :number, :default => 10

  # Timeout (in seconds) to wait for a connection to be established. Default is `10s`
  config :connect_timeout, :validate => :number, :default => 10

  # Should redirects be followed? Defaults to `true`
  config :follow_redirects, :validate => :boolean, :default => true

  # Max number of concurrent connections. Defaults to `50`
  config :pool_max, :validate => :number, :default => 50

  # Max number of concurrent connections to a single host. Defaults to `25`
  config :pool_max_per_route, :validate => :number, :default => 25

  # Turn this on to enable HTTP keepalive support. We highly recommend setting `automatic_retries` to at least
  # one with this to fix interactions with broken keepalive implementations.
  config :keepalive, :validate => :boolean, :default => true

  # How many times should the client retry a failing URL. We highly recommend NOT setting this value
  # to zero if keepalive is enabled. Some servers incorrectly end keepalives early requiring a retry!
  # Note: if `retry_non_idempotent` is set only GET, HEAD, PUT, DELETE, OPTIONS, and TRACE requests will be retried.
  config :automatic_retries, :validate => :number, :default => 5

  # If `automatic_retries` is enabled this will cause non-idempotent HTTP verbs (such as POST) to be retried.
  config :retry_non_idempotent, :validate => :boolean, :default => true

  # How long to wait before checking if the connection is stale before executing a request on a connection using keepalive.
  # # You may want to set this lower, possibly to 0 if you get connection errors regularly
  # Quoting the Apache commons docs (this client is based Apache Commmons):
  # 'Defines period of inactivity in milliseconds after which persistent connections must be re-validated prior to being leased to the consumer. Non-positive value passed to this method disables connection validation. This check helps detect connections that have become stale (half-closed) while kept inactive in the pool.'
  # See https://hc.apache.org/httpcomponents-client-ga/httpclient/apidocs/org/apache/http/impl/conn/PoolingHttpClientConnectionManager.html#setValidateAfterInactivity(int)[these docs for more info]
  config :validate_after_inactivity, :validate => :number, :default => 200

  # Enable cookie support. With this enabled the client will persist cookies
  # across requests as a normal web browser would. Enabled by default
  config :cookies, :validate => :boolean, :default => true

  # If you'd like to use an HTTP proxy . This supports multiple configuration syntaxes:
  #
  # 1. Proxy host in form: `http://proxy.org:1234`
  # 2. Proxy host in form: `{host => "proxy.org", port => 80, scheme => 'http', user => 'username@host', password => 'password'}`
  # 3. Proxy host in form: `{url =>  'http://proxy.org:1234', user => 'username@host', password => 'password'}`
  config :proxy

  # LM Portal Name
  config :portal_name, :validate => :string, :required => true

  # Username to use for HTTP auth.
  config :access_id, :validate => :string, :required => true

  # Password to use for HTTP auth
  config :access_key, :validate => :password, :required => true

  @@MAX_PAYLOAD_SIZE = 8*1024*1024

  public
  def register
    @total = 0
    @total_failed = 0
    logger.info("Initialized LogicMonitor output plugin with configuration",
                :host => @host)

  end # def register

  def client_config
    c = {
        connect_timeout: @connect_timeout,
        socket_timeout: @socket_timeout,
        request_timeout: @request_timeout,
        follow_redirects: @follow_redirects,
        automatic_retries: @automatic_retries,
        retry_non_idempotent: @retry_non_idempotent,
        check_connection_timeout: @validate_after_inactivity,
        pool_max: @pool_max,
        pool_max_per_route: @pool_max_per_route,
        cookies: @cookies,
        keepalive: @keepalive
    }

    if @proxy
      # Symbolize keys if necessary
      c[:proxy] = @proxy.is_a?(Hash) ?
                      @proxy.reduce({}) {|memo,(k,v)| memo[k.to_sym] = v; memo} :
                      @proxy
    end

    if @access_id
      if !@access_key || !@access_key.value
        raise ::LogStash::ConfigurationError, "access_id '#{@access_id}' specified without access_key!"
      end

      # Symbolize keys if necessary
      c[:auth] = {
          :access_id => @access_id,
          :access_key => @access_key.value,
          :eager => true
      }
    end
  end

  private
  def make_client
    puts client_config
    Manticore::Client.new(client_config)
  end

  public
  def client
    @client ||= make_client
  end

  public
  def close
    @client.close
  end


  def generate_auth_string(body)
    timestamp = DateTime.now.strftime('%Q')
    hash_this = "POST#{timestamp}#{body}/log/ingest"
    sign_this = OpenSSL::HMAC.hexdigest(
                  OpenSSL::Digest.new('sha256'),
                  "#{@access_key.value}",
                  hash_this
                )
    signature = Base64.strict_encode64(sign_this)
    "LMv1 #{@access_id}:#{signature}:#{timestamp}"
  end

  def send_batch(events)
    url = "https://" + @portal_name + ".logicmonitor.com/rest/log/ingest"
    body = events.to_json
    auth_string = generate_auth_string(body)
    request = client.post(url, {
        :body => body,
        :headers => {
                "Content-Type" => "application/json",
                "User-Agent" => "LM Logs Logstash Plugin",
                "Authorization" => "#{auth_string}"
        }
    })

    request.on_success do |response|
      if response.code == 202
        @total += events.length
        @logger.debug("Successfully sent ",
                      :response_code => response.code,
                      :batch_size => events.length,
                      :total_sent => @total,
                      :time => Time::now.utc)
      elsif response.code == 207
        log_failure(
          "207 HTTP code - some of the events successfully parsed, some not. ",
          :response_code => response.code,
          :url => url,
          :response_body => response.body,
          :total_failed => @total_failed)
      else
        @total_failed += 1
        log_failure(
            "Encountered non-202/207 HTTP code #{response.code}",
            :response_code => response.code,
            :url => url,
            :response_body => response.body,
            :total_failed => @total_failed)
      end
    end

    request.on_failure do |exception|
      @total_failed += 1
      log_failure("Could not access URL",
                  :url => url,
                  :method => @http_method,
                  :body => body,
                  :message => exception.message,
                  :class => exception.class.name,
                  :backtrace => exception.backtrace,
                  :total_failed => @total_failed
      )
    end

    @logger.debug("Sending LM Logs",
                  :total => @total,
                  :time => Time::now.utc)
    request.call

  rescue Exception => e
    @logger.error("[Exception=] #{e.message} #{e.backtrace}")
  end


  public
  def multi_receive(events)
    puts @@MAX_PAYLOAD_SIZE
    if debug
      puts events.to_json
    end

    events.each_slice(@batch_size) do |chunk|
      documents = []
      chunk.each do |event|
        lmlogs_event = {
          message: event.get(@message_key).to_s
        }

        lmlogs_event["_lm.resourceId"] = {}
        lmlogs_event["_lm.resourceId"]["#{@lm_property}"] = event.get(@property_key.to_s)

        if @keep_timestamp
          lmlogs_event["timestamp"] = event.get("@timestamp")
        end
        
        if @timestamp_is_key
          lmlogs_event["timestamp"] = event.get(@timestamp_key.to_s)
        end

        documents = isValidPayloadSize(documents,lmlogs_event,@@MAX_PAYLOAD_SIZE)

      end
      send_batch(documents)
    end
  end

  def log_failure(message, opts)
    @logger.error("[HTTP Output Failure] #{message}", opts)
  end

  def isValidPayloadSize(documents,lmlogs_event,max_payload_size)
    if (documents.to_json.bytesize + lmlogs_event.to_json.bytesize) >  max_payload_size 
          send_batch(documents)
          documents = []
          
    end
    documents.push(lmlogs_event)
    return documents
  end
end # class LogStash::Outputs::LMLogs
