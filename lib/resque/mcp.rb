# frozen_string_literal: true

require "json"
require "resque"
require "mcp"
require "zeitwerk"

require_relative "mcp/version"

module Resque
  module Mcp
    class Error < StandardError; end

    class << self
      def configure
        yield config
      end

      def config
        @config ||= Configuration.new
      end

      def reset_config!
        @config = Configuration.new
      end
    end
  end
end

loader = Zeitwerk::Loader.for_gem_extension(Resque)
loader.ignore("#{__dir__}/mcp/version.rb")
loader.ignore("#{__dir__}/mcp/engine.rb")
loader.setup

require_relative "mcp/engine" if defined?(Rails)
