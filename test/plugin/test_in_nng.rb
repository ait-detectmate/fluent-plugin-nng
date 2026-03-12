require "helper"
require 'fluent/plugin/in_nng.rb'

class NngInputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

#  test 'emit' do
#    config = %(
#      uri tcp://127.0.0.1:5557
#      <parse>
#        @type json
#      </parse>
#    )
#
#    d = create_driver(config)
#    d.run(timeout: 5)
#
#    d.run(expect_records: 2) do
#      tests = [
#      {'msg' => '[Sep 11 00:00:00] localhost logger: foo', 'expected' => event_time('Sep 11 00:00:00', format: '%b %d %H:%M:%S')},
#      {'msg' => '[Sep  1 00:00:00] localhost logger: foo', 'expected' => event_time('Sep  1 00:00:00', format: '%b  %d %H:%M:%S')},
#      ]
#
#      tests.each do |test|
#        send_data(test)
#      end
#    end
#
#    d.events.each do |tag, time, record|
#      assert_equal('input.test', tag)
#      assert_equal({ 'foo' => 'bar' }, record)
#      assert(time.is_a?(Fluent::EventTime))
#    end
#  end

  private

  def send_data(data)
    client = NNG::Socket.new(:pair0)
    client.dial("tcp://127.0.0.1:5557")
    client.send(data)
  end

  def create_driver(conf)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::NngInput).configure(conf)
  end
end
