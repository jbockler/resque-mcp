# frozen_string_literal: true

module Resque
  module Mcp
    module Tools
      class WorkerStats < Base
        STATES = %w[all working idle].freeze

        tool_name "worker_stats"
        description "List registered workers: state (working/idle), current job, " \
          "queues subscribed, per-worker processed/failed counts, start time. " \
          "Flags workers with expired heartbeats (likely dead)."
        input_schema(
          properties: {
            state: {type: "string", enum: ["working", "idle", "all"], default: "all"},
            offset: {type: "integer", default: 0, minimum: 0},
            limit: {type: "integer", default: 50, minimum: 1, maximum: 100}
          },
          required: []
        )
        annotations(read_only_hint: true)

        def self.call(server_context:, state: "all", offset: 0, limit: 50, **)
          unless STATES.include?(state)
            return error_response("state must be one of: #{STATES.join(", ")}")
          end

          all = adapter(server_context).workers
          counts = {
            total: all.size,
            working: all.count(&:working?),
            idle: all.count(&:idle?),
            heartbeat_expired: all.count(&:heartbeat_expired)
          }
          selected = (state == "all") ? all : all.select { |w| w.state == state }
          clamped = clamp_limit(limit)
          workers = (selected[offset, clamped] || []).map do |record|
            job = record.current_job
            record.to_h.merge(current_job: job && {
              queue: job.queue,
              class: job.class_name,
              args_preview: args_preview(job),
              run_at: job.run_at
            })
          end
          success_response({
            workers: workers,
            counts: counts,
            page: page_envelope(
              total: selected.size, offset: offset, limit: clamped,
              returned: workers.size, requested_limit: limit
            )
          }, server_context)
        end
      end
    end
  end
end
