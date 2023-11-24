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
require_relative "version"

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
  config :access_id, :validate => :string, :required => false, :default => nil

  # Include/Exclude metadata from sending to LM Logs
  config :include_metadata, :validate => :boolean, :default => false

  # Password to use for HTTP auth
  config :access_key, :validate => :password, :required => false, :default => nil

  # Use bearer token instead of access key/id for authentication.
  config :bearer_token, :validate => :password, :required => false, :default => nil

  # json keys for which plugin looks for these keys and adds as event meatadata. A dot "." can be used to add nested subjson.
  config :include_metadata_keys, :validate => :array, :required => false, :default => []

  @@MAX_PAYLOAD_SIZE = 8*1024*1024

  # For developer debugging.
  @@CONSOLE_LOGS = false

  public
  def register
    @total = 0
    @total_failed = 0
    logger.info("Initialized LogicMonitor output plugin with configuration",
                :host => @host)
    logger.info("Max Payload Size: ",
                :size => @@MAX_PAYLOAD_SIZE)
    configure_auth

    @final_metadata_keys = Hash.new
    if @include_metadata_keys.any?
      include_metadata_keys.each do | nested_key |
        @final_metadata_keys[nested_key] = nested_key.to_s.split('.')
      end
    end

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

    log_debug("manticore client config: ", :client => c)
    return c
  end

  private
  def make_client
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

  def configure_auth
    @use_bearer_instead_of_lmv1 = false
    if @access_id == nil || @access_key.value == nil
      @logger.info "Access Id or access key null. Using bearer token for authentication."
      @use_bearer_instead_of_lmv1 = true
    end
    if @use_bearer_instead_of_lmv1 && @bearer_token.value == nil
      @logger.error "Bearer token not specified. Either access_id and access_key both or bearer_token must be specified for authentication with Logicmonitor."
      raise LogStash::ConfigurationError, 'No valid authentication specified. Either access_id and access_key both or bearer_token must be specified for authentication with Logicmonitor.'
    end
  end
  def generate_auth_string(body)
    if @use_bearer_instead_of_lmv1
      return "Bearer #{@bearer_token.value}"
    else
      timestamp = DateTime.now.strftime('%Q')
      hash_this = "POST#{timestamp}#{body}/log/ingest"
      sign_this = OpenSSL::HMAC.hexdigest(
                    OpenSSL::Digest.new('sha256'),
                    "#{@access_key.value}",
                    hash_this
                  )
      signature = Base64.strict_encode64(sign_this)
      return "LMv1 #{@access_id}:#{signature}:#{timestamp}"
    end
  end

  def send_batch(events)
    log_debug("Started sending logs to LM: ",
                  :time => Time::now.utc)
    url = "https://" + @portal_name + ".logicmonitor.com/rest/log/ingest"
    body = events.to_json
    auth_string = generate_auth_string(body)
    request = client.post(url, {
        :body => body,
        :headers => {
                "Content-Type" => "application/json",
                "User-Agent" => "lm-logs-logstash/" + LmLogsLogstashPlugin::VERSION,
                "Authorization" => "#{auth_string}"
        }
    })

    request.on_success do |response|
      if response.code == 202
        @total += events.length
        log_debug("Successfully sent ",
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
      log_failure("The request failed. ",
                  :url => url,
                  :method => @http_method,
                  :message => exception.message,
                  :class => exception.class.name,
                  :backtrace => exception.backtrace,
                  :total_failed => @total_failed
      )
    end

    log_debug("Completed sending logs to LM",
                  :total => @total,
                  :time => Time::now.utc)
    request.call

  rescue Exception => e
    @logger.error("[Exception=] #{e.message} #{e.backtrace}")
  end

  def log_debug(message, *opts)
    if @@CONSOLE_LOGS
      puts "[#{DateTime::now}] [logstash.outputs.lmlogs] [DEBUG] #{message} #{opts.to_s}"
    elsif debug
      @logger.debug(message, *opts)
    end
  end

  public
  def multi_receive(events)
    if events.length() > 0
      log_debug(events.to_json)
	  end

    events.each_slice(@batch_size) do |chunk|
      documents = []
      chunk.each do |event|

        documents = isValidPayloadSize(documents, processEvent(event), @@MAX_PAYLOAD_SIZE)
      end
      send_batch(documents)
    end
  end


  def processEvent(event)
    event_json = JSON.parse(event.to_json)
    lmlogs_event = {}

    if @include_metadata
      lmlogs_event = event_json
      lmlogs_event.delete("@timestamp")  # remove redundant timestamp field
      if lmlogs_event.dig("event", "original") != nil
        lmlogs_event["event"].delete("original") # remove redundant log field
      end
    elsif @final_metadata_keys
      @final_metadata_keys.each do | key, value |
        nestedVal = event_json
        value.each { |x| nestedVal = nestedVal[x] }
        if nestedVal != nil
          lmlogs_event[key] = nestedVal
        end
      end
    end

    lmlogs_event["message"] = event.get(@message_key).to_s
    lmlogs_event["_lm.resourceId"] = {}
    lmlogs_event["_lm.resourceId"]["#{@lm_property}"] = event.get(@property_key.to_s)

    if @keep_timestamp
      lmlogs_event["timestamp"] = event.get("@timestamp")
    end

    if @timestamp_is_key
      lmlogs_event["timestamp"] = event.get(@timestamp_key.to_s)
    end

    return lmlogs_event

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
