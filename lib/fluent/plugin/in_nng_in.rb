#
# Copyright 2025- whotwagner
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fluent/plugin/input'
require 'nng'
require 'uri'

module Fluent
  module Plugin
    class NngInput < Fluent::Plugin::Input
      Fluent::Plugin.register_input('nng_in', self)

      helpers :parser, :compat_parameters, :thread

      config_param :uri, :string, default: 'tcp://127.0.0.1:5555'
      config_param :recv_timeout, :float, default: 1.0
      config_param :tag, :string, default: 'nng.input'
      # TLS-Settings
      config_param :cert, :string, default: nil
      config_param :key, :string, secret: true, default: nil
      config_param :ca, :string, default: nil
      config_param :verify, :bool, default: false
      config_param :server_name, :string, default: nil

      def configure(conf)
        if @uri !~ /\A#{URI::RFC2396_PARSER.make_regexp(['tcp', 'ipc', 'inproc', 'ws', 'tls+tcp'])}\z/
          raise Fluent::ConfigError, 'uri must be one of: tcp:// ipc:// inproc:// ws:// or tls+tcp://'
        end

        compat_parameters_convert(conf, :parser)
        parser_config = conf.elements('parse').first
        unless parser_config
          raise Fluent::ConfigError, '<parse> section is required.'
        end

        super
        log.info "parser: #{parser_config}"
        @parser = parser_create(conf: parser_config)
      end

      def initialize
        super
        @socket = nil
        @stop = false
      end

      def listen
        log.info "Starting listener at: #{@uri}"
        uri = URI(@uri)
        if uri.scheme == 'ipc'
          File.exist?(uri.path) && File.delete(uri.path)
        end
        @socket = NNG::Socket::Pair0.new
        @socket.listen(@uri, cert: @cert, key: @key, ca: @ca, verify: @verify, server_name: @server_name)
        @socket.recv_timeout = @recv_timeout
      end

      def start
        super
        listen
        thread_create(:nng_input_run, &method(:run))
      end

      def run
        log.info 'Start listening..'
        loop do
          msg = nil
          until msg
            if @stop
              return
            end

            begin
              msg = @socket.receive
            rescue Timeout::Error
              sleep 0.01
              next
            end
          end
          @parser.parse(msg) do |time, record|
            router.emit(@tag, time || Fluent::Engine.now, record)
          end
        end
      end

      def stop
        log.info 'Stopping..'
        @stop = true
        super
      end

      def shutdown
        log.info 'Initiate shutdown'
        if @socket
          log.info 'stopping nng-socket'
          @socket.close
        end
        super
      end
    end
  end
end
