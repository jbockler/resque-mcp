# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class QueueStatsTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
      end

      def test_lists_all_queues_with_sizes
        seed_jobs("imports", "ImportWorker", count: 2)
        seed_jobs("default", "SomeJob")

        response = Tools::QueueStats.call(server_context: server_context)

        refute response.error?
        content = response.structured_content
        assert_equal({"imports" => 2, "default" => 1}, content[:queues])
        assert_equal "test", content.dig(:meta, :environment)
      end

      def test_single_queue_returns_size_without_jobs
        seed_jobs("imports", "ImportWorker", count: 2)

        response = Tools::QueueStats.call(queue: "imports", server_context: server_context)

        refute response.error?
        content = response.structured_content
        assert_equal "imports", content[:queue]
        assert_equal 2, content[:size]
        refute content.key?(:jobs)
      end

      def test_include_jobs_returns_previews_and_page_envelope
        3.times { |i| seed_jobs("imports", "ImportWorker", args: [i]) }

        response = Tools::QueueStats.call(
          queue: "imports", include_jobs: true, offset: 0, limit: 2,
          server_context: server_context
        )

        refute response.error?
        content = response.structured_content
        assert_equal [
          {class: "ImportWorker", args_preview: "[0]"},
          {class: "ImportWorker", args_preview: "[1]"}
        ], content[:jobs]
        assert_equal(
          {total: 3, offset: 0, limit: 2, returned: 2, has_more: true, next_offset: 2},
          content[:page]
        )
      end

      def test_last_page_has_no_next_offset
        seed_jobs("imports", "ImportWorker", count: 3)

        response = Tools::QueueStats.call(
          queue: "imports", include_jobs: true, offset: 2, limit: 2,
          server_context: server_context
        )

        page = response.structured_content[:page]
        assert_equal 1, page[:returned]
        refute page[:has_more]
        assert_nil page[:next_offset]
      end

      def test_limit_is_clamped_with_in_band_note
        seed_jobs("imports", "ImportWorker")

        response = Tools::QueueStats.call(
          queue: "imports", include_jobs: true, limit: 150,
          server_context: server_context
        )

        page = response.structured_content[:page]
        assert_equal 100, page[:limit]
        assert_equal "limit clamped to 100", page[:note]
      end

      def test_long_args_are_truncated_in_preview
        seed_jobs("imports", "ImportWorker", args: ["x" * 500])

        response = Tools::QueueStats.call(
          queue: "imports", include_jobs: true, server_context: server_context
        )

        preview = response.structured_content[:jobs].first[:args_preview]
        marker = "… (truncated)"
        assert preview.end_with?(marker)
        assert_operator preview.length, :<=, Tools::Base::ARGS_PREVIEW_MAX + marker.length
      end

      def test_unknown_queue_returns_error_listing_known_names
        seed_jobs("imports", "ImportWorker")

        response = Tools::QueueStats.call(queue: "nope", server_context: server_context)

        assert response.error?
        assert_includes response.content.first[:text], "imports"
      end

      def test_include_jobs_without_queue_returns_error
        response = Tools::QueueStats.call(include_jobs: true, server_context: server_context)

        assert response.error?
        assert_includes response.content.first[:text], "queue"
      end

      def test_tolerates_unexpected_arguments
        response = Tools::QueueStats.call(verbose: true, server_context: server_context)

        refute response.error?
      end

      private

      def server_context
        {adapter: Adapter.new, environment: "test"}
      end
    end
  end
end
