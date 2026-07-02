# frozen_string_literal: true

module Resque
  module Mcp
    # The only code in the gem that talks to Resque. Rails-free.
    class Adapter
      def initialize(resque: ::Resque)
        @resque = resque
      end

      # One queue_sizes snapshot, not Resque.info — info reruns the queue
      # sweep, letting pending disagree with queue_sizes in one response.
      def stats
        queue_sizes = @resque.queue_sizes
        {
          pending: queue_sizes.values.sum,
          processed: @resque::Stat[:processed],
          failed: @resque::Failure.count,
          queues: queue_sizes.size,
          workers: @resque.workers.size,
          working: @resque.working.size,
          queue_sizes: queue_sizes
        }
      end

      # Resque.redis_id can embed user:password@; only this stripped form
      # may reach tool responses.
      def redis_identifier
        strip_userinfo(@resque.redis_id.to_s)
      end

      private

      # Greedy to the last "@" — passwords may contain "@", "/", or spaces;
      # over-stripping is acceptable, leaking is not.
      def strip_userinfo(id)
        id.sub(%r{\A(.*?://)?.*@}, '\1')
      end
    end
  end
end
