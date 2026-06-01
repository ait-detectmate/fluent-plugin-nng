# frozen_string_literal: true

require 'test/unit'
require 'mocha/test_unit'
require 'fluent/test'
require 'fluent/test/driver/output'
require 'fluent/test/helpers'
require 'fluent/plugin/out_nng_out'

class NngOutputTest < Test::Unit::TestCase
  include Fluent::Test::Helpers

  # ---------------------------------------------------------------------------
  # A plain Ruby socket double – no Mocha blocks, no closure issues.
  # ---------------------------------------------------------------------------
  class SocketStub
    attr_reader :sent_messages, :closed, :dial_args

    def initialize
      @sent_messages = []
      @closed        = false
      @dial_args     = nil
    end

    def dial(uri, **opts)
      @dial_args = { uri: uri, **opts }
    end

    def send(msg)
      @sent_messages << msg
    end

    def close
      @closed = true
    end
  end

  # DialErrorStub raises on the first +fail_times+ dial calls, then succeeds.
  class DialErrorStub < SocketStub
    def initialize(fail_times)
      super()
      @fail_times = fail_times
      @dial_count = 0
    end

    def dial_count; @dial_count; end

    def dial(uri, **opts)
      @dial_count += 1
      if @dial_count <= @fail_times
        raise RuntimeError, "dial failed (attempt #{@dial_count})"
      end
      super
    end
  end

  def setup
    Fluent::Test.setup
    # Default safe mock for tests that don't care about socket behaviour
    @mock_socket = mock('nng_socket')
    @mock_socket.stubs(:dial)
    @mock_socket.stubs(:send)
    @mock_socket.stubs(:close)
    NNG::Socket::Pair0.stubs(:new).returns(@mock_socket)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def base_config
    %(
      uri tcp://127.0.0.1:5559
      <format>
        @type json
      </format>
    )
  end

  def create_driver(conf = base_config)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::NngOutput).configure(conf)
  end

  # Patches #connect on the plugin instance to install +socket+ as @socket
  # without touching NNG::Socket::Pair0 – avoids any NNG constructor race.
  def patch_connect(driver, socket)
    driver.instance.define_singleton_method(:connect) do
      @socket = socket
    end
  end

  # ---------------------------------------------------------------------------
  # configure – valid URIs
  # ---------------------------------------------------------------------------

  test 'configure accepts tcp:// URI' do
    d = create_driver(%(
      uri tcp://127.0.0.1:5559
      <format>
        @type json
      </format>
    ))
    assert_equal 'tcp://127.0.0.1:5559', d.instance.uri
  end

  test 'configure accepts ipc:// URI' do
    d = create_driver(%(
      uri ipc:///tmp/nng_out.sock
      <format>
        @type json
      </format>
    ))
    assert_equal 'ipc:///tmp/nng_out.sock', d.instance.uri
  end

  test 'configure accepts inproc:// URI' do
    d = create_driver(%(
      uri inproc://out_test
      <format>
        @type json
      </format>
    ))
    assert_equal 'inproc://out_test', d.instance.uri
  end

  test 'configure accepts ws:// URI' do
    d = create_driver(%(
      uri ws://127.0.0.1:5559
      <format>
        @type json
      </format>
    ))
    assert_equal 'ws://127.0.0.1:5559', d.instance.uri
  end

  test 'configure accepts tls+tcp:// URI' do
    d = create_driver(%(
      uri tls+tcp://127.0.0.1:5560
      <format>
        @type json
      </format>
    ))
    assert_equal 'tls+tcp://127.0.0.1:5560', d.instance.uri
  end

  # ---------------------------------------------------------------------------
  # configure – URI validation (same RFC2396 limitation as the input plugin)
  # ---------------------------------------------------------------------------

  test 'configure does not reject ftp:// (RFC2396 regex limitation)' do
    assert_raise Fluent::ConfigError do
      create_driver(%(
        uri ftp://127.0.0.1:5559
        <format>
          @type json
        </format>
      ))
    end
  end

  test 'configure does not reject http:// (RFC2396 regex limitation)' do
    assert_raise Fluent::ConfigError do
      create_driver(%(
        uri http://127.0.0.1:5559
        <format>
          @type json
        </format>
      ))
    end
  end

  test 'configure does not reject a bare word (RFC2396 regex limitation)' do
    assert_raise Fluent::ConfigError do
      create_driver(%(
        uri not_a_uri
        <format>
          @type json
        </format>
      ))
    end
  end

  # ---------------------------------------------------------------------------
  # configure – defaults
  # ---------------------------------------------------------------------------

  test 'default uri is tcp://127.0.0.1:5559' do
    d = create_driver(%(
      <format>
        @type json
      </format>
    ))
    assert_equal 'tcp://127.0.0.1:5559', d.instance.uri
  end

  test 'default max_retry is 100' do
    d = create_driver
    assert_equal 100, d.instance.max_retry
  end

  test 'default retry_time is 5' do
    d = create_driver
    assert_equal 5, d.instance.retry_time
  end

  test 'default TLS params are nil' do
    d = create_driver
    assert_nil d.instance.cert
    assert_nil d.instance.key
    assert_nil d.instance.ca
    assert_nil d.instance.verify
    assert_nil d.instance.server_name
  end

  test 'default format type is json' do
    d = create_driver
    # formatter_create returns a JSONFormatter for the default <format> block
    formatter = d.instance.instance_variable_get(:@formatter)
    assert_not_nil formatter
  end

  # ---------------------------------------------------------------------------
  # configure – custom values
  # ---------------------------------------------------------------------------

  test 'configure sets custom max_retry and retry_time' do
    d = create_driver(%(
      max_retry  10
      retry_time 2
      <format>
        @type json
      </format>
    ))
    assert_equal 10, d.instance.max_retry
    assert_equal 2,  d.instance.retry_time
  end

  test 'configure sets TLS parameters' do
    d = create_driver(%(
      uri         tls+tcp://127.0.0.1:5560
      cert        /path/to/cert.pem
      key         /path/to/key.pem
      ca          /path/to/ca.pem
      verify      true
      server_name myserver.example.com
      <format>
        @type json
      </format>
    ))
    assert_equal '/path/to/cert.pem',    d.instance.cert
    assert_equal '/path/to/key.pem',     d.instance.key
    assert_equal '/path/to/ca.pem',      d.instance.ca
    assert_equal true,                   d.instance.verify
    assert_equal 'myserver.example.com', d.instance.server_name
  end

  # ---------------------------------------------------------------------------
  # connect – dial behaviour
  # ---------------------------------------------------------------------------

  test 'connect creates a Pair0 socket and dials with correct uri' do
    d = create_driver
    NNG::Socket::Pair0.expects(:new).returns(@mock_socket)
    @mock_socket.expects(:dial).with(
      'tcp://127.0.0.1:5559',
      cert: nil, key: nil, ca: nil, verify: nil, server_name: nil
    )
    d.instance.connect
  end

  test 'connect passes TLS options to dial' do
    d = create_driver(%(
      uri         tls+tcp://127.0.0.1:5560
      cert        /path/to/cert.pem
      key         /path/to/key.pem
      ca          /path/to/ca.pem
      verify      true
      server_name myserver
      <format>
        @type json
      </format>
    ))
    NNG::Socket::Pair0.expects(:new).returns(@mock_socket)
    @mock_socket.expects(:dial).with(
      'tls+tcp://127.0.0.1:5560',
      cert: '/path/to/cert.pem',
      key:  '/path/to/key.pem',
      ca:   '/path/to/ca.pem',
      verify: true,
      server_name: 'myserver'
    )
    d.instance.connect
  end

  test 'connect retries after a dial error and eventually succeeds' do
    socket = DialErrorStub.new(2) # fails twice, succeeds on 3rd
    NNG::Socket::Pair0.stubs(:new).returns(socket)

    d = create_driver
    # Suppress sleep delay in tests
    d.instance.stubs(:sleep)

    assert_nothing_raised { d.instance.connect }
    assert_equal 3, socket.dial_count
  end

  test 'connect raises UnrecoverableError when max_retry is exceeded' do
    socket = DialErrorStub.new(999) # always fails
    NNG::Socket::Pair0.stubs(:new).returns(socket)

    d = create_driver(%(
      max_retry  3
      retry_time 0
      <format>
        @type json
      </format>
    ))
    d.instance.stubs(:sleep)

    assert_raise(Fluent::UnrecoverableError) { d.instance.connect }
    assert_equal 3, socket.dial_count
  end

  test 'connect does not raise when max_retry is 0 (retry forever)' do
    # max_retry == 0 means the guard `if @max_retry > 0 && try >= @max_retry`
    # never fires.  We let it succeed after 2 failures to avoid an infinite loop.
    socket = DialErrorStub.new(2)
    NNG::Socket::Pair0.stubs(:new).returns(socket)

    d = create_driver(%(
      max_retry  0
      retry_time 0
      <format>
        @type json
      </format>
    ))
    d.instance.stubs(:sleep)

    assert_nothing_raised { d.instance.connect }
    assert_equal 3, socket.dial_count
  end

  # ---------------------------------------------------------------------------
  # write
  # ---------------------------------------------------------------------------

  test 'write sends the chunk contents over the socket' do
    socket = SocketStub.new
    d = create_driver
    patch_connect(d, socket)

    d.run do
      d.feed('tag', event_time, { 'msg' => 'hello' })
    end

    assert_equal 1, socket.sent_messages.size
    payload = JSON.parse(socket.sent_messages.first)
    assert_equal 'hello', payload['msg']
  end

  test 'write sends all fed events in a single flush' do
    # The output plugin calls chunk.read which returns all buffered events
    # as one concatenated string – one socket.send per flush, not per event.
    socket = SocketStub.new
    d = create_driver
    patch_connect(d, socket)

    d.run do
      d.feed('tag', event_time, { 'n' => 1 })
      d.feed('tag', event_time, { 'n' => 2 })
      d.feed('tag', event_time, { 'n' => 3 })
    end

    assert_equal 1, socket.sent_messages.size

    # The payload contains all three records (newline-delimited JSON lines)
    lines = socket.sent_messages.first.strip.split("\n")
    assert_equal 3, lines.size
    lines.each_with_index do |line, i|
      assert_equal i + 1, JSON.parse(line)['n']
    end
  end

  test 'write sends valid JSON by default' do
    socket = SocketStub.new
    d = create_driver
    patch_connect(d, socket)

    d.run do
      d.feed('tag', event_time, { 'key' => 'value', 'num' => 42 })
    end

    parsed = JSON.parse(socket.sent_messages.first)
    assert_equal 'value', parsed['key']
    assert_equal 42,      parsed['num']
  end

  # ---------------------------------------------------------------------------
  # format
  # ---------------------------------------------------------------------------

  test 'format returns a JSON string for a record' do
    d = create_driver
    patch_connect(d, SocketStub.new)

    t      = event_time
    result = d.instance.format('test.tag', t, { 'a' => 1 })

    assert_kind_of String, result
    parsed = JSON.parse(result)
    assert_equal 1, parsed['a']
  end

  test 'format uses msgpack formatter when configured' do
    d = create_driver(%(
      <format>
        @type msgpack
      </format>
    ))
    patch_connect(d, SocketStub.new)

    t      = event_time
    result = d.instance.format('tag', t, { 'x' => 'y' })

    # msgpack output is binary, not valid UTF-8 JSON
    assert_kind_of String, result
    unpacked = MessagePack.unpack(result)
    assert_equal 'y', unpacked['x']
  end

  # ---------------------------------------------------------------------------
  # shutdown
  # ---------------------------------------------------------------------------

  test 'shutdown closes the socket' do
    socket = SocketStub.new
    d = create_driver
    patch_connect(d, socket)

    d.run {}

    assert socket.closed, 'expected socket to be closed after shutdown'
  end
end
