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

      # DNS-rebinding protection (CVE-2026-63118): a Host outside the
      # configured allowlist is rejected before the request is handled.
      def test_disallowed_host_is_forbidden
        post_initialize_with_host("attacker.example.com")

        assert_response :forbidden
      end

      def test_allowed_host_is_accepted
        post_initialize_with_host("www.example.com")

        assert_response :ok
      end

      # A cross-origin request (Origin not same-origin with the Host and not
      # in allowed_origins) is rejected by the transport's validation.
      def test_disallowed_origin_is_forbidden
        post_initialize_with_origin("https://attacker.example.com")

        assert_response :forbidden
      end

      # mcp_transport_options are forwarded to the SDK transport: a tiny
      # max_request_bytes makes the normal initialize body too large → 413.
      def test_mcp_transport_options_are_forwarded_to_the_transport
        with_mcp_transport_options(max_request_bytes: 5) do
          post_initialize
          assert_response 413
        end
      end

      # ...but a passthrough value cannot weaken the DNS-rebinding posture:
      # disabling it via mcp_transport_options is overridden, so a bad Host still 403s.
      def test_mcp_transport_options_cannot_disable_dns_rebinding_protection
        with_mcp_transport_options(dns_rebinding_protection: false) do
          post_initialize_with_host("attacker.example.com")
          assert_response :forbidden
        end
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
