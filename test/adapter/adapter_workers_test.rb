# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class AdapterWorkersTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
        @adapter = Adapter.new
      end

      def test_no_workers_returns_empty_list
        assert_equal [], @adapter.workers
      end

      def test_idle_worker_is_normalized
        seed_worker("imports", "default", hostname: "host-a", pid: 4021)

        record = @adapter.workers.first

        assert_equal "host-a:4021:imports,default", record.id
        assert_equal "idle", record.state
        assert_equal ["imports", "default"], record.queues
        assert_kind_of String, record.started
        assert_equal 0, record.processed
        assert_equal 0, record.failed
        refute record.heartbeat_expired
        assert_nil record.current_job
      end

      def test_working_worker_carries_current_job
        worker = seed_worker("imports")
        start_working(worker, queue: "imports", klass: "ImportWorker", args: [812])

        record = @adapter.workers.first

        assert_equal "working", record.state
        job = record.current_job
        assert_equal "imports", job.queue
        assert_equal "ImportWorker", job.class_name
        assert_equal [812], job.filtered_args
        assert_kind_of String, job.run_at
      end

      def test_per_worker_processed_and_failed_counts
        worker = seed_worker("imports")
        2.times { worker.processed! }
        worker.failed!

        record = @adapter.workers.first

        assert_equal 2, record.processed
        assert_equal 1, record.failed
      end

      def test_stale_heartbeat_flags_expired
        stale = seed_worker("imports", hostname: "host-a", pid: 1)
        fresh = seed_worker("imports", hostname: "host-b", pid: 2)
        expire_heartbeat(stale)
        fresh.heartbeat!

        by_id = @adapter.workers.to_h { |r| [r.id, r] }

        assert by_id["host-a:1:imports"].heartbeat_expired
        refute by_id["host-b:2:imports"].heartbeat_expired
      end

      def test_worker_without_any_heartbeat_is_not_flagged
        seed_worker("imports")

        refute @adapter.workers.first.heartbeat_expired
      end

      def test_workers_are_sorted_by_id
        seed_worker("imports", hostname: "host-b", pid: 2)
        seed_worker("imports", hostname: "host-a", pid: 9)
        seed_worker("imports", hostname: "host-a", pid: 1)

        ids = @adapter.workers.map(&:id)

        assert_equal ids.sort, ids
      end
    end
  end
end
