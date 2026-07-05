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

      def test_queues_returns_name_to_size_hash
        seed_jobs("imports", "ImportWorker", count: 3)
        seed_jobs("default", "SomeJob")

        assert_equal({"imports" => 3, "default" => 1}, @adapter.queues)
      end

      def test_queue_size
        seed_jobs("imports", "ImportWorker", count: 2)

        assert_equal 2, @adapter.queue_size("imports")
      end

      def test_queue_size_unknown_queue_raises_with_known_names
        seed_jobs("imports", "ImportWorker")

        error = assert_raises(Adapter::UnknownQueueError) { @adapter.queue_size("nope") }
        assert_includes error.message, '"nope"'
        assert_includes error.message, "imports"
      end

      def test_peek_pages_through_pending_jobs
        3.times { |i| seed_jobs("imports", "ImportWorker", args: [i]) }

        result = @adapter.peek("imports", offset: 1, limit: 2)

        assert_equal 3, result[:size]
        assert_equal [[1], [2]], result[:jobs].map(&:filtered_args)
      end

      # Pin the resque quirk: peek with count == 1 returns a bare hash.
      def test_peek_normalizes_single_job_bare_hash
        seed_jobs("imports", "ImportWorker", args: [812])

        result = @adapter.peek("imports", offset: 0, limit: 1)

        job = result[:jobs].first
        assert_equal 1, result[:jobs].size
        assert_equal "ImportWorker", job.class_name
        assert_equal [812], job.filtered_args
        assert_equal "imports", job.queue
      end

      def test_peek_beyond_end_returns_empty_jobs
        seed_jobs("imports", "ImportWorker")

        result = @adapter.peek("imports", offset: 5, limit: 1)

        assert_equal [], result[:jobs]
        assert_equal 1, result[:size]
      end

      def test_peek_unknown_queue_raises
        assert_raises(Adapter::UnknownQueueError) { @adapter.peek("nope", offset: 0, limit: 20) }
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
