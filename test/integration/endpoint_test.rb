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
        assert_equal ["overview", "queue_stats"], tools.map { |t| t["name"] }.sort
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

      def test_non_post_verbs_are_method_not_allowed
        %i[get delete put patch options].each do |verb|
          public_send(verb, McpRequestHelpers::ENDPOINT)
          assert_response :method_not_allowed, "#{verb.upcase} should be 405"
        end
      end
    end
  end
end
