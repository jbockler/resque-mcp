# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class RetryFailureTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
      end

      def test_retries_the_record_and_reports_it_kept
        seed_failure(queue: "imports", klass: "ImportWorker", args: [812])

        response = Tools::RetryFailure.call(index: 0, server_context: server_context)

        refute response.error?
        content = response.structured_content
        assert_equal({index: 0, class: "ImportWorker", queue: "imports"}, content[:retried])
        assert_equal false, content[:record_removed]
        assert_includes content[:note], "kept"
        assert content.dig(:meta, :redis)
        refute_nil Resque::Failure.all(0, 1)["retried_at"]
        assert_equal({"class" => "ImportWorker", "args" => [812]}, Resque.peek("imports"))
      end

      def test_remove_deletes_the_record_and_the_note_warns_about_shifted_indexes
        seed_failure

        response = Tools::RetryFailure.call(index: 0, remove: true, server_context: server_context)

        refute response.error?
        content = response.structured_content
        assert_equal true, content[:record_removed]
        assert_includes content[:note], "indexes above 0 have shifted down by one"
        assert_equal 0, Resque::Failure.count
      end

      def test_stale_fingerprint_returns_error_naming_the_current_record
        seed_failure(klass: "JobA")
        set_failure_failed_at(0, "2026/07/17 10:00:00 UTC")

        response = Tools::RetryFailure.call(
          index: 0,
          expected_failed_at: "2026/07/17 09:59:59 UTC",
          server_context: server_context
        )

        assert response.error?
        assert_includes response.content.first[:text], "2026/07/17 10:00:00 UTC"
        assert_equal 0, Resque.size("default")
      end

      def test_out_of_range_index_returns_error_with_current_count
        seed_failure

        response = Tools::RetryFailure.call(index: 7, server_context: server_context)

        assert response.error?
        assert_includes response.content.first[:text], "count: 1"
      end

      def test_multi_queue_backend_without_queue_returns_error_naming_queues
        Resque::Failure.backend = Resque::Failure::RedisMultiQueue
        seed_failure(queue: "alpha")

        response = Tools::RetryFailure.call(index: 0, server_context: server_context)

        assert response.error?
        assert_includes response.content.first[:text], "alpha_failed"
      ensure
        Resque::Failure.backend = Resque::Failure::Redis
      end

      def test_tolerates_unexpected_arguments
        seed_failure

        response = Tools::RetryFailure.call(index: 0, verbose: true, server_context: server_context)

        refute response.error?
      end

      private

      def server_context
        {adapter: Adapter.new, environment: "test"}
      end
    end
  end
end
