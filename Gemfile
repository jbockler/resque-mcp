# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in resque-mcp.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

gem "standard", "~> 1.3"

gem "rails"
gem "mock_redis"

# resque still calls the pre-1.21 MultiJson API; unpin once resque migrates
# https://github.com/resque/resque/pull/1940
gem "multi_json", "< 1.21"
