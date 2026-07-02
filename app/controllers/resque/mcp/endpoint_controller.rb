# frozen_string_literal: true

module Resque
  module Mcp
    class EndpointController < ActionController::API
      before_action :require_auth_token, only: :handle

      def handle
        server = ServerFactory.build(environment: Rails.env.to_s)
        transport = ::MCP::Server::Transports::StreamableHTTPTransport.new(
          server, stateless: true, enable_json_response: true
        )

        status, headers, body = transport.handle_request(request)
        headers.each { |key, value| response.set_header(key, value) }

        payload = body.first
        if payload
          render json: payload, status: status
        else
          head status
        end
      end

      def method_not_allowed
        head :method_not_allowed
      end

      private

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
