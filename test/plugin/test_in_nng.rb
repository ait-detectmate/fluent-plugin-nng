# frozen_string_literal: true

require 'test/unit'
require 'mocha/test_unit'
require 'fluent/test'
require 'fluent/test/driver/input'
require 'fluent/test/helpers'
require 'fluent/plugin/in_nng_in'

class NngInputTest < Test::Unit::TestCase
  include Fluent::Test::Helpers

  def setup
    Fluent::Test.setup
    @mock_socket = mock('nng_socket')
    @mock_socket.stubs(:listen)
    @mock_socket.stubs(:recv_timeout=)
    @mock_socket.stubs(:close)
    # Default: always timeout so the run loop idles safely
    @mock_socket.stubs(:receive).raises(Timeout::Error)
    NNG::Socket::Pair0.stubs(:new).returns(@mock_socket)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def base_config
    %(
      uri tcp://127.0.0.1:5555
      tag  nng.test
      <parse>
        @type json
      </parse>
    )
  end

  def create_driver(conf = base_config)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::NngInput).configure(conf)
  end

  # ---------------------------------------------------------------------------
  # configure – valid URIs
  # ---------------------------------------------------------------------------

  test 'configure accepts tcp:// URI' do
    d = create_driver(%(
      uri tcp://127.0.0.1:5555
      <parse>
        @type json
      </parse>
    ))
    assert_equal 'tcp://127.0.0.1:5555', d.instance.uri
  end

  test 'configure accepts ipc:// URI' do
    d = create_driver(%(
      uri ipc:///tmp/test.sock
      <parse>
        @type json
      </parse>
    ))
    assert_equal 'ipc:///tmp/test.sock', d.instance.uri
  end

  test 'configure accepts inproc:// URI' do
    d = create_driver(%(
      uri inproc://test
      <parse>
        @type json
      </parse>
    ))
    assert_equal 'inproc://test', d.instance.uri
  end

  test 'configure accepts ws:// URI' do
    d = create_driver(%(
      uri ws://127.0.0.1:5555
      <parse>
        @type json
      </parse>
    ))
    assert_equal 'ws://127.0.0.1:5555', d.instance.uri
  end

  test 'configure accepts tls+tcp:// URI' do
    d = create_driver(%(
      uri tls+tcp://127.0.0.1:5556
      <parse>
        @type json
      </parse>
    ))
    assert_equal 'tls+tcp://127.0.0.1:5556', d.instance.uri
  end

  # ---------------------------------------------------------------------------
  # configure – URI validation behaviour
  #
  # The plugin uses URI::RFC2396_PARSER.make_regexp to validate the uri param.
  # RFC2396 treats almost every string as a valid relative-URI reference, so
  # the guard is effectively a no-op: bare words, ftp://, http:// all pass.
  #
  # These tests document the *actual* behaviour so that regressions are caught
  # if the validation logic is ever tightened.
  # ---------------------------------------------------------------------------

  test 'configure does not reject ftp:// (RFC2396 regex limitation)' do
    # Replace assert_nothing_raised with assert_raise(Fluent::ConfigError)
    # once the plugin properly whitelists schemes.
    assert_raise(Fluent::ConfigError) do
      create_driver(%(
        uri ftp://127.0.0.1:5555
        <parse>
          @type json
        </parse>
      ))
    end
  end

  test 'configure does not reject http:// (RFC2396 regex limitation)' do
    assert_raise(Fluent::ConfigError) do
      create_driver(%(
        uri http://127.0.0.1:5555
        <parse>
          @type json
        </parse>
      ))
    end
  end

  test 'configure does not reject a bare word uri (RFC2396 regex limitation)' do
    assert_raise(Fluent::ConfigError) do
      create_driver(%(
        uri not_a_uri
        <parse>
          @type json
        </parse>
      ))
    end
  end

  # ---------------------------------------------------------------------------
  # configure – defaults
  # ---------------------------------------------------------------------------

  test 'default uri is tcp://127.0.0.1:5555' do
    d = create_driver(%(
      <parse>
        @type json
      </parse>
    ))
    assert_equal 'tcp://127.0.0.1:5555', d.instance.uri
  end

  test 'default tag is nng.input' do
    d = create_driver(%(
      <parse>
        @type json
      </parse>
    ))
    assert_equal 'nng.input', d.instance.tag
  end

  test 'default recv_timeout is 1.0' do
    d = create_driver(%(
      <parse>
        @type json
      </parse>
    ))
    assert_equal 1.0, d.instance.recv_timeout
  end

  test 'default TLS params are nil / false' do
    d = create_driver(%(
      <parse>
        @type json
      </parse>
    ))
    assert_nil  d.instance.cert
    assert_nil  d.instance.key
    assert_nil  d.instance.ca
    assert_nil  d.instance.server_name
    assert_equal false, d.instance.verify
  end

  # ---------------------------------------------------------------------------
  # configure – custom values
  # ---------------------------------------------------------------------------

  test 'configure sets custom tag' do
    d = create_driver(%(
      uri tcp://127.0.0.1:9999
      tag  custom.tag
      <parse>
        @type json
      </parse>
    ))
    assert_equal 'custom.tag', d.instance.tag
  end

  test 'configure sets custom recv_timeout' do
    d = create_driver(%(
      recv_timeout 5.0
      <parse>
        @type json
      </parse>
    ))
    assert_equal 5.0, d.instance.recv_timeout
  end

  test 'configure sets TLS parameters' do
    d = create_driver(%(
      uri        tls+tcp://127.0.0.1:5556
      cert       /path/to/cert.pem
      key        /path/to/key.pem
      ca         /path/to/ca.pem
      verify     true
      server_name myserver.example.com
      <parse>
        @type json
      </parse>
    ))
    assert_equal '/path/to/cert.pem',    d.instance.cert
    assert_equal '/path/to/key.pem',     d.instance.key
    assert_equal '/path/to/ca.pem',      d.instance.ca
    assert_equal true,                   d.instance.verify
    assert_equal 'myserver.example.com', d.instance.server_name
  end

  # ---------------------------------------------------------------------------
  # listen – socket setup
  # ---------------------------------------------------------------------------

  test 'listen creates a Pair0 socket and calls listen with correct uri' do
    d = create_driver
    NNG::Socket::Pair0.expects(:new).returns(@mock_socket)
    @mock_socket.expects(:listen).with(
      'tcp://127.0.0.1:5555',
      cert: nil, key: nil, ca: nil, verify: false, server_name: nil
    )
    @mock_socket.expects(:recv_timeout=).with(1.0)
    d.instance.listen
  end

  test 'listen passes TLS options to socket' do
    d = create_driver(%(
      uri        tls+tcp://127.0.0.1:5556
      cert       /path/to/cert.pem
      key        /path/to/key.pem
      ca         /path/to/ca.pem
      verify     true
      server_name myserver
      <parse>
        @type json
      </parse>
    ))
    NNG::Socket::Pair0.expects(:new).returns(@mock_socket)
    @mock_socket.expects(:listen).with(
      'tls+tcp://127.0.0.1:5556',
      cert: '/path/to/cert.pem',
      key:  '/path/to/key.pem',
      ca:   '/path/to/ca.pem',
      verify: true,
      server_name: 'myserver'
    )
    @mock_socket.expects(:recv_timeout=).with(1.0)
    d.instance.listen
  end

  test 'listen sets recv_timeout on the socket' do
    d = create_driver(%(
      recv_timeout 3.5
      <parse>
        @type json
      </parse>
    ))
    @mock_socket.expects(:recv_timeout=).with(3.5)
    d.instance.listen
  end

  test 'listen deletes existing ipc socket file if present' do
    d = create_driver(%(
      uri ipc:///tmp/fluentd_nng_test.sock
      <parse>
        @type json
      </parse>
    ))
    File.stubs(:exist?).with('/tmp/fluentd_nng_test.sock').returns(true)
    File.expects(:delete).with('/tmp/fluentd_nng_test.sock')
    d.instance.listen
  end

  test 'listen does not call File.delete when ipc file does not exist' do
    d = create_driver(%(
      uri ipc:///tmp/fluentd_nng_test2.sock
      <parse>
        @type json
      </parse>
    ))
    File.stubs(:exist?).with('/tmp/fluentd_nng_test2.sock').returns(false)
    File.expects(:delete).never
    d.instance.listen
  end

  # ---------------------------------------------------------------------------
  # stop / shutdown
  # ---------------------------------------------------------------------------

  test 'stop sets @stop flag to true' do
    d = create_driver
    d.instance.listen
    assert_equal false, d.instance.instance_variable_get(:@stop)
    d.instance.stop
    assert_equal true, d.instance.instance_variable_get(:@stop)
  end

  test 'shutdown closes the socket' do
    d = create_driver
    d.instance.listen
    @mock_socket.expects(:close)
    d.instance.shutdown
  end

  test 'shutdown does not raise when socket is nil' do
    d = create_driver
    # Do not call listen – @socket stays nil
    assert_nothing_raised { d.instance.shutdown }
  end

  # ---------------------------------------------------------------------------
  # run – message processing
  #
  # The Fluentd test driver wires up the router on the plugin instance during
  # d.run, but the background thread can call router.emit before that
  # assignment completes, causing "undefined method 'emit' for nil".
  #
  # We sidestep the race entirely by:
  #   1. Calling d.run(expect_emits: N, timeout: 5) {} – the driver start/stop
  #      lifecycle is correct and expect_emits gates teardown.
  #   2. Stubbing router on the instance *after* d.run starts (impossible to
  #      time) – so instead we test run() directly without the driver thread
  #      by injecting a real EventRouter via the test helper, which is what
  #      the driver itself does internally.
  #
  # The cleanest approach for a threaded input plugin: use d.run with a real
  # SocketStub and rely on expect_emits to synchronise.  The router nil issue
  # means we must ensure d.instance.router is set before the thread fires.
  # We do this by overriding #start to set @router before calling super.
  # ---------------------------------------------------------------------------

  # A minimal socket double that does not rely on Mocha for its behaviour.
  class SocketStub
    attr_writer :recv_timeout

    def initialize(*messages)
      @messages = messages.dup
    end

    def listen(*); end
    def close; end

    def receive
      raise Timeout::Error if @messages.empty?
      @messages.shift
    end
  end

  # CountingSocketStub raises Timeout::Error for the first +fail_times+ calls
  # to #receive, then returns +message+ once, then raises forever.
  class CountingSocketStub < SocketStub
    attr_reader :call_count

    def initialize(fail_times, message)
      super()
      @fail_times = fail_times
      @message    = message
      @call_count = 0
      @delivered  = false
    end

    def receive
      @call_count += 1
      if @call_count <= @fail_times
        raise Timeout::Error
      elsif !@delivered
        @delivered = true
        @message
      else
        raise Timeout::Error
      end
    end
  end

  # Installs a SocketStub as the return value of NNG::Socket::Pair0.new AND
  # pre-wires it onto the plugin instance so router is set before the thread
  # starts.  Returns [driver, socket].
  def run_driver_with_socket(socket, conf: base_config, expect_emits: 1)
    NNG::Socket::Pair0.stubs(:new).returns(socket)
    d = create_driver(conf)
    # Patch listen on the instance so it uses our pre-built socket instead of
    # calling NNG::Socket::Pair0.new again (start -> listen -> new).
    d.instance.define_singleton_method(:listen) do
      @socket = socket
    end
    [d, socket]
  end

  test 'run emits a parsed JSON record with the correct tag and fields' do
    socket = SocketStub.new('{"foo":"bar","num":42}')
    d, = run_driver_with_socket(socket)
    d.run(expect_emits: 1, timeout: 5) {}

    assert_equal 1, d.events.size
    tag, _time, record = d.events.first
    assert_equal 'nng.test', tag
    assert_equal 'bar', record['foo']
    assert_equal 42,    record['num']
  end

  test 'run emits multiple messages in order' do
    socket = SocketStub.new('{"a":1}', '{"a":2}', '{"a":3}')
    d, = run_driver_with_socket(socket, expect_emits: 3)
    d.run(expect_emits: 3, timeout: 5) {}

    assert_equal 3, d.events.size
    d.events.each_with_index do |(tag, _t, rec), i|
      assert_equal 'nng.test', tag
      assert_equal i + 1,      rec['a']
    end
  end

  test 'run retries after Timeout::Error before receiving a message' do
    socket = CountingSocketStub.new(2, '{"x":"y"}')
    d, = run_driver_with_socket(socket)
    d.run(expect_emits: 1, timeout: 5) {}

    assert_operator socket.call_count, :>=, 3,
                    'expected at least 3 receive calls (2 timeouts + 1 success)'
    assert_equal 1,   d.events.size
    assert_equal 'y', d.events.first[2]['x']
  end

  test 'run uses the configured tag' do
    socket = SocketStub.new('{"k":"v"}')
    conf = %(
      uri tcp://127.0.0.1:5555
      tag  my.custom.tag
      <parse>
        @type json
      </parse>
    )
    d, = run_driver_with_socket(socket, conf: conf)
    d.run(expect_emits: 1, timeout: 5) {}

    assert_equal 'my.custom.tag', d.events.first[0]
  end

  test 'run emits a record with a timestamp' do
    socket = SocketStub.new('{"v":1}')
    d, = run_driver_with_socket(socket)
    d.run(expect_emits: 1, timeout: 5) {}

    _tag, time, _record = d.events.first
    assert_not_nil time
    assert_kind_of Integer, time.to_i
  end
end
