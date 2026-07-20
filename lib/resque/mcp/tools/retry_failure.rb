# frozen_string_literal: true

module Resque
  module Mcp
    module Tools
      class RetryFailure < Base
        tool_name "retry_failure"
        description "Re-enqueue one failed job onto its original queue (Resque marks " \
          "it retried_at but keeps the failure record). Set remove: true to also " \
          "delete the record after re-enqueueing. Pass expected_failed_at from the " \
          "record you inspected — the call aborts if the index no longer points at " \
          "that job."
        input_schema(
          properties: {
            index: {type: "integer", minimum: 0},
            remove: {type: "boolean", default: false, description: "Delete the failure record after re-enqueueing"},
            expected_failed_at: {type: "string", description: "failed_at of the record you inspected; strongly recommended — indexes shift on removals"},
            expected_class: {type: "string"},
            expected_queue: {type: "string"},
            queue: {type: "string", description: "Failure queue (only relevant with the redis_multi_queue backend; use the same value as in list_failures)"}
          },
          required: ["index"]
        )
        annotations(destructive_hint: true, idempotent_hint: false)

        def self.call(index:, server_context:, remove: false, queue: nil,
          expected_failed_at: nil, expected_class: nil, expected_queue: nil, **)
          record = adapter(server_context).requeue_failure(
            index,
            remove: remove,
            queue: queue,
            expected_failed_at: expected_failed_at,
            expected_class: expected_class,
            expected_queue: expected_queue
          )
          note = if remove
            "Failure record deleted; indexes above #{index} have shifted down by one — re-list before acting again."
          else
            "Failure record kept with retried_at stamp; indexes unchanged."
          end
          success_response({
            retried: {index: record.index, class: record.job.class_name, queue: record.queue},
            record_removed: remove,
            note: note
          }, server_context)
        rescue Adapter::FailureOutOfRangeError, Adapter::FailureQueueRequiredError,
          Adapter::StaleFailureIndexError, ArgumentError => e
          error_response(e.message)
        end
      end
    end
  end
end
