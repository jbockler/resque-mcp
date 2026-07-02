# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class OverviewTest < Minitest::Test
      include ResqueTestHelpers

      def setup
        reset_resque!
      end

      def test_returns_stats_with_meta_footer
        seed_jobs("imports", "ImportWorker", count: 2)

        response = Tools::Overview.call(server_context: server_context)

        refute response.error?
        content = response.structured_content
        assert_equal 2, content[:pending]
        assert_equal({"imports" => 2}, content[:queue_sizes])
        assert_equal "test", content.dig(:meta, :environment)
        assert content.dig(:meta, :redis), "meta footer must name the redis target"
      end

      def test_text_content_mirrors_structured_content
        seed_jobs("imports", "ImportWorker", count: 2)

        response = Tools::Overview.call(server_context: server_context)

        assert_equal JSON.generate(response.structured_content), response.content.first[:text]
      end

      def test_tolerates_unexpected_arguments
        response = Tools::Overview.call(verbose: true, server_context: server_context)

        refute response.error?
      end

      private

      def server_context
        {adapter: Adapter.new, environment: "test"}
      end
    end
  end
end
