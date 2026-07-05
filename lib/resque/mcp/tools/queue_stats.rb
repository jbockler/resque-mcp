# frozen_string_literal: true

module Resque
  module Mcp
    module Tools
      class QueueStats < Base
        tool_name "queue_stats"
        description "List queues with sizes. Pass `queue` to inspect one queue and " \
          "optionally page through its pending jobs (`include_jobs: true`)."
        input_schema(
          properties: {
            queue: {type: "string", description: "Inspect a single queue by name"},
            include_jobs: {type: "boolean", default: false, description: "Include pending job payloads (only with queue)"},
            offset: {type: "integer", default: 0, minimum: 0},
            limit: {type: "integer", default: 20, minimum: 1, maximum: 100}
          },
          required: []
        )
        annotations(read_only_hint: true)

        def self.call(server_context:, queue: nil, include_jobs: false, offset: 0, limit: 20, **)
          if queue.nil?
            return error_response("include_jobs requires queue") if include_jobs
            return success_response({queues: adapter(server_context).queues}, server_context)
          end

          unless include_jobs
            size = adapter(server_context).queue_size(queue)
            return success_response({queue: queue, size: size}, server_context)
          end

          clamped = clamp_limit(limit)
          result = adapter(server_context).peek(queue, offset: offset, limit: clamped)
          jobs = result[:jobs].map do |job|
            {class: job.class_name, args_preview: args_preview(job)}
          end
          success_response({
            queue: queue,
            size: result[:size],
            jobs: jobs,
            page: page_envelope(
              total: result[:size], offset: offset, limit: clamped,
              returned: jobs.size, requested_limit: limit
            )
          }, server_context)
        rescue Adapter::UnknownQueueError => e
          error_response(e.message)
        end
      end
    end
  end
end
