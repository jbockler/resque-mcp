# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class ListFailuresTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
      end

      def test_returns_compact_records_without_backtrace
        seed_failure(queue: "imports", klass: "ImportWorker", args: [812], message: "boom")

        response = Tools::ListFailures.call(server_context: server_context)

        refute response.error?
        failure = response.structured_content[:failures].first
        assert_equal 0, failure[:index]
        assert_equal "ImportWorker", failure[:class]
        assert_equal "[812]", failure[:args_preview]
        assert_equal "RuntimeError", failure[:exception]
        assert_includes failure[:error], "boom"
        refute failure.key?(:backtrace), "list records must not carry backtraces"
        refute failure.key?(:args), "list records carry previews, not full args"
      end

      def test_long_error_is_truncated_with_in_band_mark
        seed_failure(message: "x" * 500)

        response = Tools::ListFailures.call(server_context: server_context)

        error = response.structured_content[:failures].first[:error]
        assert error.end_with?("… (truncated)")
        assert_operator error.length, :<, 300
      end

      def test_page_envelope_uses_adapter_cursor
        3.times { seed_failure(klass: "JobA") }

        response = Tools::ListFailures.call(limit: 2, server_context: server_context)

        page = response.structured_content[:page]
        assert_equal({total: 3, offset: 0, limit: 2, returned: 2, has_more: true, next_offset: 2}, page)
      end

      def test_filtered_page_carries_scan_note_and_raw_cursor
        4.times { |i| seed_failure(klass: (i.even? ? "JobA" : "JobB")) }

        response = Tools::ListFailures.call(class_name: "JobA", limit: 1, server_context: server_context)

        page = response.structured_content[:page]
        assert_equal 2, page[:total]
        assert_equal "scan", page[:total_note]
        assert page[:has_more]
        # Raw cursor: one raw position consumed to find the newest JobA
        # (index 3 is JobB, index 2 is JobA) => cursor 2, not match-count 1.
        assert_equal 2, page[:next_offset]
      end

      def test_limit_is_clamped_with_note
        seed_failure

        response = Tools::ListFailures.call(limit: 150, server_context: server_context)

        page = response.structured_content[:page]
        assert_equal 100, page[:limit]
        assert_equal "limit clamped to 100", page[:note]
      end

      def test_queue_argument_on_default_backend_returns_error
        seed_failure

        response = Tools::ListFailures.call(queue: "imports", server_context: server_context)

        assert response.error?
      end

      def test_multi_queue_backend_without_queue_returns_error_naming_queues
        Resque::Failure.backend = Resque::Failure::RedisMultiQueue
        seed_failure(queue: "alpha")

        response = Tools::ListFailures.call(server_context: server_context)

        assert response.error?
        assert_includes response.content.first[:text], "alpha_failed"
      ensure
        Resque::Failure.backend = Resque::Failure::Redis
      end

      def test_tolerates_unexpected_arguments
        response = Tools::ListFailures.call(verbose: true, server_context: server_context)

        refute response.error?
      end

      def test_filters_configured_parameters_out_of_args_preview
        seed_failure(args: [{"password" => "hunter2", "batch" => 7}])

        response = with_filter_parameters([:password]) do
          Tools::ListFailures.call(server_context: server_context)
        end

        preview = response.structured_content[:failures].first[:args_preview]
        refute_includes preview, "hunter2"
        assert_includes preview, "[FILTERED]"
        assert_includes preview, "7"
      end

      # There is no synthetic wrapper key: a filter matching "args" must
      # not blank out entire argument lists.
      def test_filters_matching_the_word_args_do_not_mask_everything
        seed_failure(args: [812, {"target" => "s3://bucket"}])

        response = with_filter_parameters(["args"]) do
          Tools::ListFailures.call(server_context: server_context)
        end

        assert_equal "[812,{\"target\":\"s3://bucket\"}]",
          response.structured_content[:failures].first[:args_preview]
      end

      private

      def server_context
        {adapter: Adapter.new, environment: "test"}
      end
    end
  end
end
