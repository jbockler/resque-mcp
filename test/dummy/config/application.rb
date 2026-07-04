# frozen_string_literal: true

require "rails"
require "action_controller/railtie"
require "resque/mcp"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.secret_key_base = "dummy-test-secret"
    config.filter_parameters += [:password]
    config.logger = ActiveSupport::Logger.new(nil)
  end
end
