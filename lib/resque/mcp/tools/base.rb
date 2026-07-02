# frozen_string_literal: true

module Resque
  module Mcp
    module Tools
      # Shared tool helpers: adapter access, response envelopes, meta footer,
      # pagination and size caps (size policy lives here, not in tools).
      class Base < ::MCP::Tool
        LIMIT_MAX = 100
        ARGS_PREVIEW_MAX = 200

        class << self
          private

          def adapter(server_context)
            server_context.fetch(:adapter)
          end

          def clamp_limit(limit)
            [limit, LIMIT_MAX].min
          end

          def page_envelope(total:, offset:, limit:, returned:, requested_limit: limit)
            has_more = offset + returned < total
            page = {
              total: total, offset: offset, limit: limit, returned: returned,
              has_more: has_more, next_offset: has_more ? offset + returned : nil
            }
            page[:note] = "limit clamped to #{LIMIT_MAX}" if requested_limit > limit
            page
          end

          def args_preview(args)
            json = JSON.generate(args)
            return json if json.length <= ARGS_PREVIEW_MAX
            "#{json[0, ARGS_PREVIEW_MAX]}… (truncated)"
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
