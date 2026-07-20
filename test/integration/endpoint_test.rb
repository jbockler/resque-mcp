# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class EndpointTest < ActionDispatch::IntegrationTest
      include ResqueTestHelpers
      include McpRequestHelpers

      def test_initialize_handshake_returns_server_info
        post_initialize

        assert_response :ok
        result = response.parsed_body.fetch("result")
        assert_equal "resque-mcp", result.dig("serverInfo", "name")
        assert_equal Resque::Mcp::VERSION, result.dig("serverInfo", "version")
      end

      def test_tools_list_names_the_registered_tools
        post_jsonrpc(method: "tools/list")

        assert_response :ok
        tools = response.parsed_body.dig("result", "tools")
        assert_equal ["get_failure", "list_failures", "overview", "queue_stats", "retry_failure", "worker_stats"],
          tools.map { |t| t["name"] }.sort
        retry_tool = tools.find { |t| t["name"] == "retry_failure" }
        assert retry_tool.dig("annotations", "destructiveHint")
      end

      def test_worker_stats_tool_call_round_trips
        reset_resque!
        worker = seed_worker("imports", hostname: "host-a", pid: 4021)
        start_working(worker, queue: "imports", klass: "ImportWorker", args: [812])

        post_jsonrpc(method: "tools/call", params: {name: "worker_stats", arguments: {}})

        assert_response :ok
        result = response.parsed_body.fetch("result")
        refute result["isError"]
        content = result.fetch("structuredContent")
        assert_equal 1, content.dig("counts", "working")
        record = content["workers"].first
        assert_equal "host-a:4021:imports", record["id"]
        assert_equal "[812]", record.dig("current_job", "args_preview")
      end

      def test_failure_tools_round_trip
        reset_resque!
        seed_failure(queue: "imports", klass: "ImportWorker", args: [812], message: "boom")

        post_jsonrpc(method: "tools/call", params: {
          name: "list_failures", arguments: {}
        })
        assert_response :ok
        result = response.parsed_body.fetch("result")
        refute result["isError"]
        failure = result.dig("structuredContent", "failures").first
        assert_equal 0, failure["index"]
        assert_equal "ImportWorker", failure["class"]
        refute failure.key?("backtrace")

        post_jsonrpc(method: "tools/call", params: {
          name: "get_failure", arguments: {index: 0}
        }, id: 2)
        assert_response :ok
        result = response.parsed_body.fetch("result")
        refute result["isError"]
        content = result.fetch("structuredContent")
        assert_equal [812], content["args"]
        assert_kind_of Array, content["backtrace"]
      end

      def test_retry_failure_tool_call_round_trips
        reset_resque!
        seed_failure(queue: "imports", klass: "ImportWorker", args: [812])

        post_jsonrpc(method: "tools/call", params: {
          name: "retry_failure", arguments: {index: 0}
        })

        assert_response :ok
        result = response.parsed_body.fetch("result")
        refute result["isError"]
        content = result.fetch("structuredContent")
        assert_equal "ImportWorker", content.dig("retried", "class")
        assert_equal false, content["record_removed"]
        refute_nil Resque::Failure.all(0, 1)["retried_at"]
        assert_equal({"class" => "ImportWorker", "args" => [812]}, Resque.peek("imports"))
      end

      def test_queue_stats_tool_call_round_trips
        reset_resque!
        seed_jobs("imports", "ImportWorker", count: 2, args: [812])

        post_jsonrpc(method: "tools/call", params: {
          name: "queue_stats",
          arguments: {queue: "imports", include_jobs: true, limit: 1}
        })

        assert_response :ok
        result = response.parsed_body.fetch("result")
        refute result["isError"]
        content = result.fetch("structuredContent")
        assert_equal 2, content["size"]
        assert_equal [{"class" => "ImportWorker", "args_preview" => "[812]"}], content["jobs"]
        assert_equal 1, content.dig("page", "next_offset")
      end

      def test_overview_tool_call_round_trips
        reset_resque!
        seed_jobs("imports", "ImportWorker", count: 2)

        post_jsonrpc(method: "tools/call", params: {name: "overview", arguments: {}})

        assert_response :ok
        result = response.parsed_body.fetch("result")
        refute result["isError"]
        content = result.fetch("structuredContent")
        assert_equal 2, content["pending"]
        assert_equal({"imports" => 2}, content["queue_sizes"])
        assert_equal "test", content.dig("meta", "environment")
      end

      def test_args_are_filtered_via_rails_filter_parameters_by_default
        reset_resque!
        seed_failure(args: [{"password" => "hunter2", "batch" => 7}])

        post_jsonrpc(method: "tools/call", params: {name: "get_failure", arguments: {index: 0}})

        assert_response :ok
        refute_includes response.body, "hunter2"
        args = response.parsed_body.dig("result", "structuredContent", "args")
        assert_equal "[FILTERED]", args.first["password"]
        assert_equal 7, args.first["batch"]
      end

      def test_explicit_gem_config_replaces_the_rails_filter_list
        reset_resque!
        seed_failure(args: [{"password" => "hunter2"}])

        with_filter_parameters([]) do
          post_jsonrpc(method: "tools/call", params: {name: "get_failure", arguments: {index: 0}})
        end

        args = response.parsed_body.dig("result", "structuredContent", "args")
        assert_equal "hunter2", args.first["password"],
          "explicit filter_parameters must replace, not merge with, the Rails list"
      end

      def test_non_post_verbs_are_method_not_allowed
        %i[get delete put patch options].each do |verb|
          public_send(verb, McpRequestHelpers::ENDPOINT)
          assert_response :method_not_allowed, "#{verb.upcase} should be 405"
        end
      end
    end
  end
end
