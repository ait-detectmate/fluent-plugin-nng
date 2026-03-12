require 'fluent/plugin/formatter'
require 'fluent/plugin/schemas_pb'
require 'google/protobuf'
require 'securerandom'

module Fluent::Plugin
  class DetectMateFormatter < Formatter
    Fluent::Plugin.register_formatter('detectmate', self)

    def configure(conf)
      super
      log.info("Configuring DetectmateFormatter")
    end

    # This is the method that formats the data output.
    def format(tag, time, record)
      log.info("Formatting using DetectmateFormatter")
      
      msg = LogSchema.new(
        logID: SecureRandom.uuid,
        log: record["message"],
      )
      msg.hostname = record["hostname"] if record.has_key? "hostname"
      msg.logSource = record["logSource"] if record.has_key? "logSource"
      LogSchema.encode(msg)
    end
  end
end
