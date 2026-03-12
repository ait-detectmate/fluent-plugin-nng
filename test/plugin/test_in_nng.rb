require "helper"
require "fluent/plugin/in_nng.rb"

class NngInputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

  test "failure" do
    flunk
  end

  private

  def create_driver(conf)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::NngInput).configure(conf)
  end
end
