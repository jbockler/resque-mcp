# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class WorkerStatsTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
      end

      def test_lists_workers_with_counts
        idle = seed_worker("default", hostname: "host-b", pid: 911)
        idle.heartbeat!
        working = seed_worker("imports", "default", hostname: "host-a", pid: 4021)
        start_working(working, queue: "imports", klass: "ImportWorker", args: [812])

        response = Tools::WorkerStats.call(server_context: server_context)

        refute response.error?
        content = response.structured_content
        assert_equal(
          {total: 2, working: 1, idle: 1, heartbeat_expired: 0},
          content[:counts]
        )
        first = content[:workers].first
        assert_equal "host-a:4021:imports,default", first[:id]
        assert_equal "working", first[:state]
        assert_equal(
          {queue: "imports", class: "ImportWorker", args_preview: "[812]", run_at: first.dig(:current_job, :run_at)},
          first[:current_job]
        )
        assert_nil content[:workers].last[:current_job]
        assert_equal "test", content.dig(:meta, :environment)
      end

      def test_state_filter_selects_and_pages_only_matching_workers
        working = seed_worker("imports", hostname: "host-a", pid: 1)
        start_working(working)
        seed_worker("default", hostname: "host-b", pid: 2)

        response = Tools::WorkerStats.call(state: "idle", server_context: server_context)

        content = response.structured_content
        assert_equal ["host-b:2:default"], content[:workers].map { |w| w[:id] }
        assert_equal 1, content.dig(:page, :total)
        assert_equal 2, content.dig(:counts, :total), "counts stay global under a state filter"
      end

      def test_invalid_state_returns_error
        response = Tools::WorkerStats.call(state: "dead", server_context: server_context)

        assert response.error?
        assert_includes response.content.first[:text], "working, idle"
      end

      def test_expired_heartbeat_is_flagged_and_counted
        stale = seed_worker("imports", hostname: "host-a", pid: 1)
        expire_heartbeat(stale)

        response = Tools::WorkerStats.call(server_context: server_context)

        content = response.structured_content
        assert content[:workers].first[:heartbeat_expired]
        assert_equal 1, content.dig(:counts, :heartbeat_expired)
      end

      def test_pagination_envelope_and_limit_clamp
        3.times { |i| seed_worker("default", hostname: "host", pid: i) }

        response = Tools::WorkerStats.call(offset: 2, limit: 150, server_context: server_context)

        page = response.structured_content[:page]
        assert_equal(
          {total: 3, offset: 2, limit: 100, returned: 1, has_more: false, next_offset: nil,
           note: "limit clamped to 100"},
          page
        )
      end

      def test_offset_beyond_total_returns_empty_page
        seed_worker("default")

        response = Tools::WorkerStats.call(offset: 5, limit: 2, server_context: server_context)

        content = response.structured_content
        assert_equal [], content[:workers]
        refute content.dig(:page, :has_more)
      end

      def test_current_job_args_are_filtered
        worker = seed_worker("imports")
        start_working(worker, args: [{"password" => "hunter2", "batch" => 7}])

        response = with_filter_parameters([:password]) do
          Tools::WorkerStats.call(server_context: server_context)
        end

        preview = response.structured_content[:workers].first.dig(:current_job, :args_preview)
        refute_includes preview, "hunter2"
        assert_includes preview, "[FILTERED]"
      end

      def test_tolerates_unexpected_arguments
        response = Tools::WorkerStats.call(verbose: true, server_context: server_context)

        refute response.error?
      end

      private

      def server_context
        {adapter: Adapter.new, environment: "test"}
      end
    end
  end
end
