# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class AdapterFailuresTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
        @adapter = Adapter.new
      end

      def test_offset_zero_is_the_newest_failure
        3.times { |i| seed_failure(klass: "JobA", args: [i]) }

        result = @adapter.failures(offset: 0, limit: 2)

        assert_equal [[2], [1]], result[:records].map { |r| r.job.filtered_args }
        assert_equal [2, 1], result[:records].map { |r| r.index }
        assert_equal 3, result[:total]
        assert result[:has_more]
        assert_equal 2, result[:next_offset]
      end

      def test_offset_near_the_end_returns_the_partial_oldest_page
        3.times { |i| seed_failure(args: [i]) }

        result = @adapter.failures(offset: 2, limit: 2)

        assert_equal [[0]], result[:records].map { |r| r.job.filtered_args }
        assert_equal [0], result[:records].map { |r| r.index }
        refute result[:has_more]
        assert_nil result[:next_offset]
      end

      def test_offset_beyond_total_returns_empty_page
        seed_failure

        result = @adapter.failures(offset: 5, limit: 2)

        assert_equal [], result[:records]
        assert_equal 1, result[:total]
        refute result[:has_more]
        assert_nil result[:next_offset]
      end

      def test_total_smaller_than_limit_returns_everything
        2.times { |i| seed_failure(args: [i]) }

        result = @adapter.failures(offset: 0, limit: 20)

        assert_equal [[1], [0]], result[:records].map { |r| r.job.filtered_args }
        refute result[:has_more]
        assert_nil result[:next_offset]
      end

      def test_limit_one_normalizes_the_bare_hash
        seed_failure(args: [812])

        result = @adapter.failures(offset: 0, limit: 1)

        assert_equal [[812]], result[:records].map { |r| r.job.filtered_args }
      end

      def test_records_are_fully_normalized
        seed_failure(queue: "imports", klass: "ImportWorker", args: [812], message: "boom")

        record = @adapter.failures(offset: 0, limit: 1)[:records].first

        assert_equal 0, record.index
        assert_equal "imports", record.queue
        assert_equal "ImportWorker", record.job.class_name
        assert_equal [812], record.job.filtered_args
        assert_equal "RuntimeError", record.exception
        assert_includes record.error, "boom"
        assert_kind_of Array, record.backtrace
        refute_empty record.backtrace
        assert record.failed_at
        assert record.worker
        assert_nil record.retried_at
      end

      def test_filtered_paging_walks_all_matches_without_skip_or_repeat
        # Interleave two classes so matches are non-contiguous raw indexes.
        10.times do |i|
          seed_failure(klass: (i.even? ? "JobA" : "JobB"), args: [i])
        end

        seen = []
        offset = 0
        loop do
          result = @adapter.failures(offset: offset, limit: 2, class_name: "JobA")
          seen.concat(result[:records].map { |r| r.job.filtered_args.first })
          assert_operator result[:records].size, :<=, 2
          break unless result[:has_more]
          offset = result[:next_offset]
        end

        assert_equal [8, 6, 4, 2, 0], seen
      end

      def test_filtered_total_counts_only_matches_and_is_marked_as_scan
        seed_failure(klass: "JobA")
        seed_failure(klass: "JobB")
        seed_failure(klass: "JobA")

        result = @adapter.failures(offset: 0, limit: 20, class_name: "JobA")

        assert_equal 2, result[:total]
        assert_equal "scan", result[:total_note]
        assert_equal [2, 0], result[:records].map { |r| r.index }
        refute result[:has_more]
      end

      def test_filtered_ids_are_raw_list_indexes
        seed_failure(klass: "JobB")
        seed_failure(klass: "JobA")

        result = @adapter.failures(offset: 0, limit: 20, class_name: "JobA")

        assert_equal [1], result[:records].map { |r| r.index }
      end

      def test_filtered_scan_crosses_chunk_boundaries
        count = Adapter::FILTER_SCAN_CHUNK + 5
        count.times { |i| seed_failure(klass: ((i % 50 == 0) ? "Rare" : "Common"), args: [i]) }

        result = @adapter.failures(offset: 0, limit: 20, class_name: "Rare")

        assert_equal [100, 50, 0], result[:records].map { |r| r.job.filtered_args.first }
        refute result[:has_more]
      end

      def test_failure_returns_the_full_record_by_raw_id
        seed_failure(klass: "JobA", args: [0])
        seed_failure(klass: "JobB", args: [1])

        record = @adapter.failure(0)

        assert_equal "JobA", record.job.class_name
        assert_equal [0], record.job.filtered_args
      end

      def test_failure_out_of_range_raises_with_current_count
        seed_failure

        error = assert_raises(Adapter::FailureOutOfRangeError) { @adapter.failure(5) }
        assert_includes error.message, "5"
        assert_includes error.message, "count: 1"
      end

      def test_failure_on_empty_list_raises
        error = assert_raises(Adapter::FailureOutOfRangeError) { @adapter.failure(0) }
        assert_includes error.message, "count: 0"
      end

      # A removal between the count read and the fetch must surface as
      # out-of-range, not a nil-deref.
      def test_failure_vanishing_between_count_and_fetch_raises_out_of_range
        failure_stub = Class.new do
          def self.count(*) = 1

          def self.all(*) = nil

          def self.backend = Resque::Failure::Redis
        end
        stub = Module.new
        stub.const_set(:Failure, failure_stub)

        assert_raises(Adapter::FailureOutOfRangeError) do
          Adapter.new(resque: stub).failure(0)
        end
      end
    end

    # count(nil) sums all failure queues but all(..., nil) reads the empty
    # default list — the adapter must demand an explicit failure queue.
    class AdapterMultiQueueFailuresTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
        Resque::Failure.backend = Resque::Failure::RedisMultiQueue
        @adapter = Adapter.new
      end

      def teardown
        Resque::Failure.backend = Resque::Failure::Redis
      end

      def test_failures_without_queue_raises_naming_the_failure_queues
        seed_failure(queue: "alpha")
        seed_failure(queue: "beta")

        error = assert_raises(Adapter::FailureQueueRequiredError) do
          @adapter.failures(offset: 0, limit: 20)
        end
        assert_includes error.message, "alpha_failed"
        assert_includes error.message, "beta_failed"
      end

      def test_failures_with_queue_pages_that_queue_newest_first
        seed_failure(queue: "alpha", args: [0])
        seed_failure(queue: "beta", args: [1])
        seed_failure(queue: "alpha", args: [2])

        result = @adapter.failures(offset: 0, limit: 20, queue: "alpha_failed")

        assert_equal [[2], [0]], result[:records].map { |r| r.job.filtered_args }
        assert_equal 2, result[:total]
        refute result[:has_more]
      end

      def test_failure_without_queue_raises
        seed_failure(queue: "alpha")

        assert_raises(Adapter::FailureQueueRequiredError) { @adapter.failure(0) }
      end

      def test_failure_with_queue_returns_the_record_by_per_queue_index
        seed_failure(queue: "alpha", args: [812])
        seed_failure(queue: "beta", args: [999])

        record = @adapter.failure(0, queue: "alpha_failed")

        assert_equal [812], record.job.filtered_args
      end
    end
  end
end
