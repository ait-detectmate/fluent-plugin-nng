require 'fluent/plugin/output'
require 'nng'

module Fluent::Plugin
  class NngOutput < Fluent::Plugin::Output
    Fluent::Plugin.register_output('nng_out', self)

    helpers :formatter, :inject, :compat_parameters

    config_param :uri, :string, default: 'tcp://127.0.0.1:5559'
    config_param :max_retry, :integer, default: 100
    config_param :retry_time, :integer, default: 5
    # TLS-Settings
    config_param :cert, :string, default: nil
    config_param :key, :string, secret: true, default: nil
    config_param :ca, :string, default: nil
    config_param :verify, :bool, default: nil # needs to be nil!
    config_param :server_name, :string, default: nil

    config_section :format do
      config_set_default :@type, 'json'
    end

    def initialize
      super
      @formatter = nil
      log.debug 'Initializing'
    end

    def configure(conf)
      log.debug 'configuring..'
      compat_parameters_convert(conf, :formatter, :inject)
      if @uri !~ /\A#{URI::RFC2396_PARSER.make_regexp(['tcp', 'ipc', 'inproc', 'ws', 'tls+tcp'])}\z/
        raise Fluent::ConfigError, 'uri must be one of: tcp:// ipc:// inproc:// ws:// or tls+tcp://'
      end

      super
      log.info 'Creating formatter'
      @formatter = formatter_create
      log.info 'Formatter loaded'
    end

    def start
      super
      log.info "Initiating connection to: #{@uri}"
      connect
    end

    def write(chunk)
      @socket.send(chunk.read)
    end

    def connect
      @socket = NNG::Socket::Pair0.new
      try = 0

      begin
        @socket.dial(@uri, cert: @cert, key: @key, ca: @ca, verify: @verify, server_name: @server_name)
      rescue => e
        log.error(e)
        log.info("Retry in #{@retry_time} sec")
        sleep(@retry_time)
        try += 1
        if @max_retry > 0 && try >= @max_retry
          raise Fluent::UnrecoverableError, e.message
        end

        retry
      end
    end

    def format(tag, time, record)
      injected_record = inject_values_to_record(tag, time, record)
      @formatter.format(tag, time, injected_record)
    end

    def shutdown
      log.info('Shutdown socket')
      @socket.close
      super()
    end
  end
end
