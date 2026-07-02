# frozen_string_literal: true

require "mock_redis"

Resque.redis = MockRedis.new
