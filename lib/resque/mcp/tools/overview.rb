# frozen_string_literal: true

module Resque
  module Mcp
    module Tools
      class Overview < Base
        tool_name "overview"
        description "Global Resque health snapshot: pending/processed/failed totals, " \
          "queue count, worker counts, Redis server, environment. Cheap; call this first."
        input_schema(properties: {}, required: [])
        annotations(read_only_hint: true)

        # `**` tolerates unexpected client arguments, which would otherwise
        # surface as opaque JSON-RPC internal errors.
        def self.call(server_context:, **)
          success_response(adapter(server_context).stats, server_context)
        end
      end
    end
  end
end
