require 'fluent/plugin/parser'
require 'google/protobuf'
require 'fluent/plugin/schemas_pb'

module Fluent::Plugin
  class DetectMateParser < Parser
    Fluent::Plugin.register_parser('detectmate', self)

    def configure(conf)
      super
    end

    def parse(text)
       record = LogSchema.decode(text)
       time = @estimate_current_event ? Fluent::EventTime.now : nil
       yield time, record.to_h
    end
  end
end
