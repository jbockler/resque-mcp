# frozen_string_literal: true

module Resque
  module Mcp
    class EndpointController < ActionController::API
      before_action :require_auth_token, only: :handle

      def handle
        server = ServerFactory.build(environment: Rails.env.to_s)
        config = Resque::Mcp.config
        # Passthrough first; our security-critical keys override, so nothing
        # in mcp_transport_options can weaken the DNS-rebinding posture.
        options = config.mcp_transport_options.merge(
          stateless: true,
          enable_json_response: true,
          dns_rebinding_protection: true,
          allowed_hosts: config.allowed_hosts,
          allowed_origins: config.allowed_origins
        )
        transport = ::MCP::Server::Transports::StreamableHTTPTransport.new(server, **options)

        status, headers, body = transport.handle_request(request)
        render_transport_response(status, headers, body)
      end

      def method_not_allowed
        head :method_not_allowed
      end

      private

      # Rack 3 forbids these on a response; the transport's SSE headers carry
      # `connection: keep-alive`, which some proxies then mishandle.
      HOP_BY_HOP_HEADERS = %w[
        connection keep-alive proxy-authenticate proxy-authorization
        te trailer transfer-encoding upgrade
      ].freeze

      # A per-request server with `stateless: true` has no cross-request
      # notification source, so a long-lived stream could only emit keepalives;
      # the transport hands one back as a callable Rack body (today only for
      # `subscriptions/listen`, SEP-2575), which this endpoint declines.
      def render_transport_response(status, headers, body)
        # No transport headers here: they describe the stream we are declining.
        if body.respond_to?(:call)
          return render json: {
            jsonrpc: "2.0",
            id: jsonrpc_request_id,
            error: {
              code: -32601,
              message: "Method not found: #{jsonrpc_method_label} is not supported by this stateless endpoint"
            }
          }, status: :not_implemented
        end

        headers.each do |key, value|
          next if HOP_BY_HOP_HEADERS.include?(key.to_s.downcase)
          response.set_header(key, value)
        end

        payload = body.first
        return head status unless payload

        content_type = transport_content_type(headers)
        if content_type && !content_type.start_with?("application/json")
          render body: payload, content_type: content_type, status: status
        else
          render json: payload, status: status
        end
      end

      # The transport has already consumed the raw body, but ActionDispatch
      # rewinds before parsing, so the request id is still recoverable — and a
      # JSON-RPC error with a null id cannot be correlated by a strict client.
      def jsonrpc_request_id
        id = params[:id]
        id if id.is_a?(String) || id.is_a?(Integer)
      rescue ActionDispatch::Http::Parameters::ParseError
        nil
      end

      def jsonrpc_method_label
        method_name = begin
          params[:method]
        rescue ActionDispatch::Http::Parameters::ParseError
          nil
        end
        method_name.is_a?(String) ? method_name : "this method"
      end

      def transport_content_type(headers)
        _, value = headers.find { |key, _| key.to_s.casecmp("content-type").zero? }
        value
      end

      # No reliable boot-time hook exists (initializer ordering), so a
      # missing token is caught per request: 503, never silently open.
      def require_auth_token
        configured = Resque::Mcp.config.auth_token
        if configured.blank?
          Rails.logger.error(
            "resque-mcp: refusing to serve — Resque::Mcp.config.auth_token is not set. " \
            "Set it in an initializer via Resque::Mcp.configure."
          )
          return head :service_unavailable
        end

        provided = request.authorization.to_s[/\ABearer (.+)\z/i, 1]
        unless provided && ActiveSupport::SecurityUtils.secure_compare(provided, configured)
          response.set_header("WWW-Authenticate", "Bearer")
          head :unauthorized
        end
      end
    end
  end
end
