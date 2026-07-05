# frozen_string_literal: true

require "test_helper"
require "pp"

module Resque
  module Mcp
    class JobModelTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
      end

      def test_raw_args_have_no_public_reader
        job = Models::Job.new(class_name: "ImportWorker", args: [{"password" => "hunter2"}])

        refute_respond_to job, :args
      end

      def test_filtered_args_masks_configured_keys
        job = Models::Job.new(class_name: "ImportWorker", args: [{"password" => "hunter2", "batch" => 7}])

        filtered = with_filter_parameters([:password]) { job.filtered_args }

        assert_equal [{"password" => "[FILTERED]", "batch" => 7}], filtered
      end

      def test_filtered_args_is_memoized
        calls = 0
        counting_filter = ->(key, value) { calls += 1 }
        job = Models::Job.new(class_name: "ImportWorker", args: [{"batch" => 7}])

        with_filter_parameters([counting_filter]) do
          job.filtered_args
          job.filtered_args
        end

        assert_equal 1, calls
      end

      # Debug/serialization surfaces must not undo the sealing: default
      # #inspect renders ivars, pp bypasses #inspect, and ActiveSupport's
      # Object#to_json serializes instance variables via #as_json.
      def test_inspect_pp_and_json_do_not_leak_raw_args
        job = Models::Job.new(class_name: "ImportWorker", args: [{"password" => "hunter2"}])

        with_filter_parameters([:password]) do
          refute_includes job.inspect, "hunter2"
          refute_includes PP.pp(job, +""), "hunter2"
          refute_includes job.to_json, "hunter2"
          assert_equal [{"password" => "[FILTERED]"}], job.as_json["args"]
        end
      end

      def test_failure_and_worker_inspect_do_not_leak_nested_job_args
        job = Models::Job.new(class_name: "ImportWorker", args: [{"password" => "hunter2"}])
        failure = Models::Failure.new(index: 0, failed_at: "x", queue: "imports",
          exception: "E", error: "e", backtrace: [], worker: "w", retried_at: nil, job: job)
        worker = Models::Worker.new(id: "h:1:imports", state: "working", queues: ["imports"],
          started: "x", processed: 0, failed: 0, heartbeat_expired: false, current_job: job)

        refute_includes failure.inspect, "hunter2"
        refute_includes worker.inspect, "hunter2"
      end

      def test_raising_host_filter_fails_closed
        job = Models::Job.new(class_name: "ImportWorker", args: [{"password" => "hunter2"}])

        filtered = with_filter_parameters([->(k, v) { raise TypeError }]) { job.filtered_args }

        assert_equal "[args withheld: filter_parameters raised TypeError]", filtered
        refute_includes filtered.inspect, "hunter2"
      end
    end
  end
end
