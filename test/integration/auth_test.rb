# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class AuthTest < ActionDispatch::IntegrationTest
      include McpRequestHelpers

      def test_missing_token_is_unauthorized
        post_initialize(authorization: nil)

        assert_response :unauthorized
        assert_equal "Bearer", response.headers["WWW-Authenticate"]
      end

      def test_wrong_token_is_unauthorized
        post_initialize(authorization: "Bearer wrong-token")

        assert_response :unauthorized
        assert_equal "Bearer", response.headers["WWW-Authenticate"]
      end

      def test_non_bearer_authorization_is_unauthorized
        post_initialize(authorization: "Basic dGVzdC10b2tlbg==")

        assert_response :unauthorized
      end

      def test_valid_token_is_accepted
        post_initialize

        assert_response :ok
        assert response.parsed_body.key?("result")
      end

      def test_bearer_scheme_is_case_insensitive
        post_initialize(authorization: "bearer #{Resque::Mcp.config.auth_token}")

        assert_response :ok
      end

      def test_blank_configured_token_is_service_unavailable
        original = Resque::Mcp.config.auth_token
        Resque::Mcp.config.auth_token = ""
        post_initialize(authorization: "Bearer #{original}")

        assert_response :service_unavailable
      ensure
        Resque::Mcp.config.auth_token = original
      end
    end
  end
end
