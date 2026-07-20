# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class AdapterRequeueTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
        @adapter = Adapter.new
      end

      def test_requeue_stamps_retried_at_and_reenqueues_the_job
        seed_failure(queue: "imports", klass: "ImportWorker", args: [812])

        result = @adapter.requeue_failure(0)

        assert_equal 0, result.index
        assert_equal "ImportWorker", result.job.class_name
        assert_equal "imports", result.queue
        assert_equal 1, Resque::Failure.count, "the record must be kept"
        refute_nil Resque::Failure.all(0, 1)["retried_at"]
        assert_equal({"class" => "ImportWorker", "args" => [812]}, Resque.peek("imports"))
      end

      def test_remove_reenqueues_deletes_the_record_and_shifts_indexes_above
        seed_failure(args: [0])
        seed_failure(queue: "imports", klass: "ImportWorker", args: [1])
        seed_failure(args: [2])

        result = @adapter.requeue_failure(1, remove: true)

        assert_equal "ImportWorker", result.job.class_name
        assert_equal 2, Resque::Failure.count
        assert_equal [[0], [2]], (0..1).map { |i| @adapter.failure(i).job.filtered_args }
        assert_equal({"class" => "ImportWorker", "args" => [1]}, Resque.peek("imports"))
      end

      def test_out_of_range_index_raises_with_current_count
        seed_failure

        error = assert_raises(Adapter::FailureOutOfRangeError) { @adapter.requeue_failure(7) }

        assert_includes error.message, "count: 1"
        assert_equal 0, Resque.size("default")
      end

      # The pinned race: the record at the inspected index is replaced by
      # its same-class/same-queue neighbor after a concurrent removal — the
      # failed_at fingerprint must refuse, and nothing may be written.
      def test_stale_failed_at_fingerprint_aborts_without_writing
        3.times { seed_failure(klass: "JobA") }
        (0..2).each { |i| set_failure_failed_at(i, "2026/07/17 10:00:0#{i} UTC") }
        inspected = @adapter.failure(1)
        Resque::Failure.remove(0)

        error = assert_raises(Adapter::StaleFailureIndexError) do
          @adapter.requeue_failure(1, expected_failed_at: inspected.failed_at)
        end

        assert_includes error.message, "2026/07/17 10:00:02 UTC",
          "the error must say what is at the index now"
        assert_equal 0, Resque.size("default"), "no job may be enqueued"
        assert Resque::Failure.all(0, 2).none? { |item| item["retried_at"] },
          "no record may be stamped"
      end

      # Documents why failed_at is the primary fingerprint: after the same
      # concurrent removal, class/queue still match the shifted neighbor.
      def test_class_and_queue_alone_cannot_catch_a_shifted_neighbor
        3.times { seed_failure(klass: "JobA") }
        Resque::Failure.remove(0)

        @adapter.requeue_failure(1, expected_class: "JobA", expected_queue: "default")

        assert_equal 1, Resque.size("default")
      end

      def test_matching_fingerprint_proceeds
        seed_failure(queue: "imports", klass: "ImportWorker")
        record = @adapter.failure(0)

        @adapter.requeue_failure(0,
          expected_failed_at: record.failed_at,
          expected_class: "ImportWorker",
          expected_queue: "imports")

        assert_equal 1, Resque.size("imports")
      end

      def test_mismatched_expected_class_aborts
        seed_failure(klass: "JobA")

        assert_raises(Adapter::StaleFailureIndexError) do
          @adapter.requeue_failure(0, expected_class: "JobB")
        end
        assert_equal 0, Resque.size("default")
      end

      # research §1.1: on the default backend the facade's failure-queue
      # slot accepts only nil or "failed".
      def test_wrong_failure_queue_name_on_default_backend_raises
        seed_failure

        assert_raises(ArgumentError) { @adapter.requeue_failure(0, queue: "default_failed") }
      end
    end

    class AdapterMultiQueueRequeueTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
        Resque::Failure.backend = Resque::Failure::RedisMultiQueue
        @adapter = Adapter.new
      end

      def teardown
        Resque::Failure.backend = Resque::Failure::Redis
      end

      def test_requeue_without_queue_raises_naming_the_failure_queues
        seed_failure(queue: "alpha")

        error = assert_raises(Adapter::FailureQueueRequiredError) do
          @adapter.requeue_failure(0)
        end
        assert_includes error.message, "alpha_failed"
      end

      def test_requeue_with_queue_acts_on_that_failure_queue_only
        seed_failure(queue: "alpha", klass: "AlphaJob")
        seed_failure(queue: "beta", klass: "BetaJob")

        @adapter.requeue_failure(0, queue: "alpha_failed", remove: true)

        assert_equal 0, Resque::Failure.count("alpha_failed")
        assert_equal 1, Resque::Failure.count("beta_failed")
        assert_equal({"class" => "AlphaJob", "args" => []}, Resque.peek("alpha"))
        assert_equal 0, Resque.size("beta")
      end
    end
  end
end
