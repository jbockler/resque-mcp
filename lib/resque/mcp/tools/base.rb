# frozen_string_literal: true

module Resque
  module Mcp
    module Tools
      # Shared tool helpers: adapter access, response envelopes, meta footer.
      class Base < ::MCP::Tool
        class << self
          private

          def adapter(server_context)
            server_context.fetch(:adapter)
          end

          def success_response(payload, server_context)
            body = payload.merge(meta: meta_footer(server_context))
            ::MCP::Tool::Response.new(
              [{type: "text", text: JSON.generate(body)}],
              structured_content: body
            )
          end

          def error_response(message)
            ::MCP::Tool::Response.new([{type: "text", text: message}], error: true)
          end

          def meta_footer(server_context)
            {
              environment: server_context[:environment],
              redis: adapter(server_context).redis_identifier
            }
          end
        end
      end
    end
  end
end
