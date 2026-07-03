# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class GetFailureTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
      end

      def test_returns_the_full_record
        seed_failure(queue: "imports", klass: "ImportWorker", args: [812, "s3://bucket/batch-7.csv"])

        response = Tools::GetFailure.call(index: 0, server_context: server_context)

        refute response.error?
        content = response.structured_content
        assert_equal 0, content[:index]
        assert_equal "imports", content[:queue]
        assert_equal "ImportWorker", content[:class]
        assert_equal [812, "s3://bucket/batch-7.csv"], content[:args]
        assert_equal "RuntimeError", content[:exception]
        assert_kind_of Array, content[:backtrace]
        refute_empty content[:backtrace]
        assert_equal 0, content[:backtrace_omitted]
        assert content[:worker]
        assert_nil content[:retried_at]
      end

      def test_backtrace_is_capped_at_thirty_frames
        seed_failure
        # Inflate the stored backtrace beyond the cap.
        item = Resque::Failure.all(0, 1)
        item["backtrace"] = Array.new(47) { |i| "app/lib/deep.rb:#{i}:in 'call'" }
        Resque.data_store.update_item_in_failed_queue(0, Resque.encode(item))

        response = Tools::GetFailure.call(index: 0, server_context: server_context)

        content = response.structured_content
        assert_equal 30, content[:backtrace].size
        assert_equal 17, content[:backtrace_omitted]
      end

      def test_oversized_args_are_truncated_with_in_band_mark
        seed_failure(args: ["x" * 10_000])

        response = Tools::GetFailure.call(index: 0, server_context: server_context)

        args = response.structured_content[:args]
        assert_kind_of String, args
        assert args.end_with?("… (truncated)")
      end

      def test_out_of_range_id_returns_error_with_current_count
        seed_failure

        response = Tools::GetFailure.call(index: 7, server_context: server_context)

        assert response.error?
        assert_includes response.content.first[:text], "count: 1"
      end

      def test_multi_queue_backend_without_queue_returns_error_naming_queues
        Resque::Failure.backend = Resque::Failure::RedisMultiQueue
        seed_failure(queue: "alpha")

        response = Tools::GetFailure.call(index: 0, server_context: server_context)

        assert response.error?
        assert_includes response.content.first[:text], "alpha_failed"
      ensure
        Resque::Failure.backend = Resque::Failure::Redis
      end

      def test_tolerates_unexpected_arguments
        seed_failure

        response = Tools::GetFailure.call(index: 0, verbose: true, server_context: server_context)

        refute response.error?
      end

      private

      def server_context
        {adapter: Adapter.new, environment: "test"}
      end
    end
  end
end
