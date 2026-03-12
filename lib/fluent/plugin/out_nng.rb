require 'fluent/plugin/output'
require 'nng'


module Fluent::Plugin
  class NngOutput < Fluent::Plugin::Output
    Fluent::Plugin.register_output('nng', self)

    helpers :formatter, :inject, :compat_parameters

    config_param :uri, :string, default: 'tcp://127.0.0.1:5559'
    config_param :max_retry, :integer, default: 5

    config_section :format do
      config_set_default :@type, 'json'
    end

    def initialize
      super
      @formatter = nil
    end

    def configure(conf)
      compat_parameters_convert(conf, :formatter, :inject)
      if @uri !~ /\A#{URI::regexp(['tcp', 'ipc', 'inproc', 'ws', 'tls+tcp'])}\z/
        raise Fluent::ConfigError, 'uri must be one of: tcp:// ipc:// inproc:// ws:// or tls+tcp://'
      end

      super
      @formatter = formatter_create
    end

    def start
      super
      log.info "Starting listener at: #{@uri}"
      connect
    end

    def write(chunk)
      @socket.send(chunk.read)
    end

    def connect
      @socket = NNG::Socket.new(:pair0)
      try = 0

      begin
        @socket.dial(@uri)
      rescue NNG::Error => e
        log.error(e)
        log.info("Retry in 5sec")
        sleep(5)
        try += 1
        if try >= @max_retry
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
      log.info("Shutdown socket")
      @socket.close
      super()
    end
  end
end
