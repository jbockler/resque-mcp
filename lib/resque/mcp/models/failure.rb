# frozen_string_literal: true

module Resque
  module Mcp
    module Models
      # One failed-job record. `index` is the record's mutable position in
      # the Redis failed list, not a stable id. `failed_at`/`retried_at`
      # are opaque strings. `job` is a Models::Job (sealed args); the
      # origin queue lives here, not on the job.
      Failure = Data.define(
        :index, :failed_at, :queue, :exception, :error,
        :backtrace, :worker, :retried_at, :job
      )
    end
  end
end
