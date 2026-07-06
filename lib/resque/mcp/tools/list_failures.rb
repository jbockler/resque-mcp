# frozen_string_literal: true

module Resque
  module Mcp
    module Tools
      class ListFailures < Base
        tool_name "list_failures"
        description "Page through failed jobs, newest first. Compact records without " \
          "backtraces — use get_failure for full detail. Each record's `index` is its " \
          "position in the failed list, not a stable id: indexes shift when failures " \
          "are removed, so re-list after any removal. Continue paging with the " \
          "returned page.next_offset — do not compute offsets yourself."
        input_schema(
          properties: {
            offset: {type: "integer", default: 0, minimum: 0},
            limit: {type: "integer", default: 20, minimum: 1, maximum: 100},
            class_name: {type: "string", description: "Only failures of this job class"},
            queue: {type: "string", description: "Failure queue (only relevant with the redis_multi_queue backend)"}
          },
          required: []
        )
        annotations(read_only_hint: true)

        def self.call(server_context:, offset: 0, limit: 20, class_name: nil, queue: nil, **)
          clamped = clamp_limit(limit)
          result = adapter(server_context).failures(
            offset: offset, limit: clamped, class_name: class_name, queue: queue
          )
          failures = result[:records].map do |record|
            {
              index: record.index,
              failed_at: record.failed_at,
              queue: record.queue,
              class: record.job.class_name,
              args_preview: args_preview(record.job),
              exception: record.exception,
              error: truncated_error(record.error),
              retried_at: record.retried_at
            }
          end
          success_response({
            failures: failures,
            page: page_envelope(
              total: result[:total], offset: offset, limit: clamped,
              returned: failures.size, requested_limit: limit,
              has_more: result[:has_more], next_offset: result[:next_offset],
              total_note: result[:total_note]
            )
          }, server_context)
        rescue Adapter::FailureQueueRequiredError, ArgumentError => e
          error_response(e.message)
        end
      end
    end
  end
end
