# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require_relative "dummy/config/environment"

require "rails/test_help"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }
