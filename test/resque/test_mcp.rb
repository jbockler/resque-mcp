# frozen_string_literal: true

require "test_helper"

class Resque::TestMcp < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Resque::Mcp::VERSION
  end
end
