# frozen_string_literal: true

module Resque
  module Mcp
    module Tools
      # Shared tool helpers: adapter access, response envelopes, meta footer,
      # pagination and size caps (size policy lives here, not in tools).
      class Base < ::MCP::Tool
        LIMIT_MAX = 100
        ARGS_PREVIEW_MAX = 200
        ERROR_TRUNCATE_MAX = 200
        BACKTRACE_MAX_FRAMES = 30
        ARGS_FULL_MAX = 4096

        class << self
          private

          def adapter(server_context)
            server_context.fetch(:adapter)
          end

          def clamp_limit(limit)
            [limit, LIMIT_MAX].min
          end

          # has_more/next_offset default to offset arithmetic; tools whose
          # adapter owns the cursor semantics (failures) pass them in.
          def page_envelope(total:, offset:, limit:, returned:, requested_limit: limit,
            has_more: nil, next_offset: :compute, total_note: nil)
            has_more = offset + returned < total if has_more.nil?
            next_offset = has_more ? offset + returned : nil if next_offset == :compute
            page = {
              total: total, offset: offset, limit: limit, returned: returned,
              has_more: has_more, next_offset: next_offset
            }
            page[:note] = "limit clamped to #{LIMIT_MAX}" if requested_limit > limit
            page[:total_note] = total_note if total_note
            page
          end

          def args_preview(args)
            truncate_text(JSON.generate(filter_args(args)), ARGS_PREVIEW_MAX)
          end

          def full_args(args)
            args = filter_args(args)
            json = JSON.generate(args)
            (json.length <= ARGS_FULL_MAX) ? args : truncate_text(json, ARGS_FULL_MAX)
          end

          # Key-based filtering (filter_parameters) runs BEFORE any
          # preview/truncation so a secret can't survive inside a truncated
          # JSON string. Each hash arg is filtered as its own root, so
          # anchored dot-notation filters (/\Acredit_card\.code\z/) match
          # exactly as they do in Rails log filtering. Only hash keys can
          # match — bare positional scalars pass through. A raising host
          # filter (e.g. a proc assuming string values) fails CLOSED:
          # args are withheld with an in-band mark, never leaked.
          def filter_args(args)
            filter_value(Resque::Mcp.config.param_filter, args)
          rescue => e
            "[args withheld: filter_parameters raised #{e.class}]"
          end

          def filter_value(param_filter, value)
            case value
            when Hash then param_filter.filter(value)
            when Array then value.map { |element| filter_value(param_filter, element) }
            else value
            end
          end

          def truncated_error(error)
            error.nil? ? nil : truncate_text(error, ERROR_TRUNCATE_MAX)
          end

          # => [frames, omitted_count]
          def capped_backtrace(frames)
            frames = frames.is_a?(Array) ? frames : []
            omitted = [frames.size - BACKTRACE_MAX_FRAMES, 0].max
            [frames.first(BACKTRACE_MAX_FRAMES), omitted]
          end

          def truncate_text(text, max)
            return text if text.length <= max
            "#{text[0, max]}… (truncated)"
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
