# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class AdapterTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
        @adapter = Adapter.new
      end

      def test_stats_reflects_seeded_state
        seed_jobs("imports", "ImportWorker", count: 3, args: [812])
        seed_jobs("default", "SomeJob")
        seed_worker("imports")

        stats = @adapter.stats

        assert_equal 4, stats[:pending]
        assert_equal 2, stats[:queues]
        assert_equal 1, stats[:workers]
        assert_equal 0, stats[:working]
        assert_equal 0, stats[:failed]
        assert_equal({"imports" => 3, "default" => 1}, stats[:queue_sizes])
      end

      def test_stats_on_empty_resque
        stats = @adapter.stats

        assert_equal 0, stats[:pending]
        assert_equal 0, stats[:queues]
        assert_equal({}, stats[:queue_sizes])
      end

      # mock_redis reports a junk identifier, so stripping is tested against
      # a stub that only answers redis_id.
      def test_redis_identifier_strips_userinfo_from_url
        adapter = adapter_with_redis_id("redis://user:secret@prod-redis:6379/0/resque")
        assert_equal "redis://prod-redis:6379/0/resque", adapter.redis_identifier
      end

      def test_redis_identifier_strips_userinfo_without_scheme
        adapter = adapter_with_redis_id("user:secret@prod-redis:6379")
        assert_equal "prod-redis:6379", adapter.redis_identifier
      end

      def test_redis_identifier_passes_through_without_userinfo
        adapter = adapter_with_redis_id("redis://prod-redis:6379/0/resque")
        assert_equal "redis://prod-redis:6379/0/resque", adapter.redis_identifier
      end

      def test_redis_identifier_strips_password_containing_at_sign
        adapter = adapter_with_redis_id("redis://user:p@ssw0rd@prod-redis:6379/0")
        assert_equal "redis://prod-redis:6379/0", adapter.redis_identifier
      end

      def test_redis_identifier_strips_password_containing_slash
        adapter = adapter_with_redis_id("redis://user:pa/ss@prod-redis:6379/0")
        assert_equal "redis://prod-redis:6379/0", adapter.redis_identifier
      end

      def test_redis_identifier_strips_password_containing_space
        adapter = adapter_with_redis_id("redis://user:pa ss@prod-redis:6379/0")
        assert_equal "redis://prod-redis:6379/0", adapter.redis_identifier
      end

      def test_redis_identifier_strips_userinfo_from_inspect_style_id
        adapter = adapter_with_redis_id("<Redis::Namespace v1.11.0 with client v5.4.1 for redis://u:p@host:6379>")
        refute_includes adapter.redis_identifier, "u:p"
        assert_includes adapter.redis_identifier, "host:6379"
      end

      private

      def adapter_with_redis_id(id)
        stub = Object.new
        stub.define_singleton_method(:redis_id) { id }
        Adapter.new(resque: stub)
      end
    end
  end
end
