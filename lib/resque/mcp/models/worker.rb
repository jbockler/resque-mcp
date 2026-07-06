# frozen_string_literal: true

module Resque
  module Mcp
    module Models
      # One registered worker. `started` is an opaque string.
      # `current_job` is a Models::Job (with queue/run_at) or nil.
      Worker = Data.define(
        :id, :state, :queues, :started, :processed, :failed,
        :heartbeat_expired, :current_job
      ) do
        def working? = state == "working"

        def idle? = state == "idle"
      end
    end
  end
end
