# frozen_string_literal: true

module Resque
  module Mcp
    module Tools
      class GetFailure < Base
        tool_name "get_failure"
        description "Full detail for one failed job by list index (as returned by " \
          "list_failures — indexes shift when failures are removed): complete args, " \
          "exception, backtrace (capped at 30 frames), worker that failed it."
        input_schema(
          properties: {
            index: {type: "integer", minimum: 0},
            queue: {type: "string", description: "Failure queue (only relevant with the redis_multi_queue backend; use the same value as in list_failures)"}
          },
          required: ["index"]
        )
        annotations(read_only_hint: true)

        def self.call(index:, server_context:, queue: nil, **)
          record = adapter(server_context).failure(index, queue: queue)
          backtrace, omitted = capped_backtrace(record[:backtrace])
          success_response({
            index: record[:index],
            failed_at: record[:failed_at],
            queue: record[:queue],
            class: record[:class],
            args: full_args(record[:args]),
            exception: record[:exception],
            error: record[:error],
            backtrace: backtrace,
            backtrace_omitted: omitted,
            worker: record[:worker],
            retried_at: record[:retried_at]
          }, server_context)
        rescue Adapter::FailureOutOfRangeError, Adapter::FailureQueueRequiredError, ArgumentError => e
          error_response(e.message)
        end
      end
    end
  end
end
