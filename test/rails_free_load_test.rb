# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    # Every other test boots the dummy Rails app, so the Rails-free load
    # path is only exercised in a subprocess.
    class RailsFreeLoadTest < Minitest::Test
      def test_gem_loads_and_stays_rails_free_without_rails
        lib = File.expand_path("../lib", __dir__)
        output = IO.popen(
          [Gem.ruby, "-I", lib, "-e", <<~RUBY], err: [:child, :out], &:read
            require "resque/mcp"
            abort "Rails got loaded by the gem" if defined?(Rails)
            print Resque::Mcp::VERSION
          RUBY
        )

        assert $?.success?, output
        assert_equal Resque::Mcp::VERSION, output
      end
    end
  end
end
