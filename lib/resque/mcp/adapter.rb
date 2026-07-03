# frozen_string_literal: true

module Resque
  module Mcp
    # The only code in the gem that talks to Resque. Rails-free.
    class Adapter
      class UnknownQueueError < StandardError
        def initialize(queue, known_queues)
          known = known_queues.empty? ? "(none)" : known_queues.sort.join(", ")
          super("Unknown queue #{queue.inspect}. Known queues: #{known}")
        end
      end

      class FailureOutOfRangeError < StandardError
        def initialize(index, count)
          super("No failure at index #{index}. Current failure count: #{count}" \
            "#{" (valid indexes 0..#{count - 1})" if count > 0}.")
        end
      end

      class FailureQueueRequiredError < StandardError
        def initialize(known_queues)
          super("The redis_multi_queue failure backend is active — pass `queue` " \
            "with one of the failure queues: #{known_queues.sort.join(", ")}.")
        end
      end

      # Chunk size for the tail-backwards scan under a class_name filter.
      FILTER_SCAN_CHUNK = 100

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

      def queues
        @resque.queue_sizes
      end

      def queue_size(queue)
        ensure_known_queue!(queue)
        @resque.size(queue)
      end

      def peek(queue, offset:, limit:)
        ensure_known_queue!(queue)
        {size: @resque.size(queue), jobs: to_array(@resque.peek(queue, offset, limit))}
      end

      # Newest-first pagination over the failed list. `offset` counts raw
      # list positions back from the newest record; returned indexes are raw
      # list positions (what requeue/remove take). Failures are RPUSH'd so
      # index 0 is the OLDEST record, and Failure.each's 'desc' only
      # reverses within a fetched slice — the newest-first window has to be
      # translated to raw indexes here.
      def failures(offset:, limit:, class_name: nil, queue: nil)
        ensure_failure_queue!(queue)
        raw_total = @resque::Failure.count(queue)
        if class_name.nil?
          unfiltered_failures(offset, limit, raw_total, queue)
        else
          filtered_failures(offset, limit, raw_total, class_name, queue)
        end
      end

      def failure(index, queue: nil)
        ensure_failure_queue!(queue)
        count = @resque::Failure.count(queue)
        raise FailureOutOfRangeError.new(index, count) unless index >= 0 && index < count
        item = to_array(@resque::Failure.all(index, 1, queue)).first
        # The list can shrink between the count read and the fetch.
        raise FailureOutOfRangeError.new(index, @resque::Failure.count(queue)) if item.nil?
        normalize_failure(index, item)
      end

      # Resque.redis_id can embed user:password@; only this stripped form
      # may reach tool responses.
      def redis_identifier
        strip_userinfo(@resque.redis_id.to_s)
      end

      private

      def unfiltered_failures(offset, limit, raw_total, queue)
        available = raw_total - offset
        if available <= 0
          return {records: [], total: raw_total, has_more: false, next_offset: nil}
        end
        count = [limit, available].min
        raw_start = raw_total - offset - count
        items = to_array(@resque::Failure.all(raw_start, count, queue))
        records = items.each_with_index
          .reject { |item, _i| item.nil? }
          .map { |item, i| normalize_failure(raw_start + i, item) }
          .reverse
        has_more = offset + count < raw_total
        {
          records: records,
          total: raw_total,
          has_more: has_more,
          next_offset: has_more ? offset + count : nil
        }
      end

      # Scans the list tail-backwards in chunks collecting class_name
      # matches. next_offset is a RAW cursor (raw positions consumed from
      # the newest end), not a match count — page arithmetic on it is
      # invalid, callers must pass it back verbatim.
      def filtered_failures(offset, limit, raw_total, class_name, queue)
        records = []
        cursor_after_last = nil
        has_more = false
        pos = offset
        while pos < raw_total && !has_more
          chunk_size = [FILTER_SCAN_CHUNK, raw_total - pos].min
          raw_start = raw_total - pos - chunk_size
          items = to_array(@resque::Failure.all(raw_start, chunk_size, queue))
          items.reverse_each do |item|
            index = raw_total - pos - 1
            pos += 1
            next unless item && item.dig("payload", "class") == class_name
            if records.size < limit
              records << normalize_failure(index, item)
              cursor_after_last = pos
            else
              has_more = true
              break
            end
          end
        end
        {
          records: records,
          total: @resque::Failure.count(queue, class_name),
          total_note: "scan",
          has_more: has_more,
          next_offset: has_more ? cursor_after_last : nil
        }
      end

      def normalize_failure(index, item)
        payload = item["payload"] || {}
        {
          index: index,
          failed_at: item["failed_at"],
          queue: item["queue"],
          class: payload["class"],
          args: payload["args"],
          exception: item["exception"],
          error: item["error"],
          backtrace: item["backtrace"],
          worker: item["worker"],
          retried_at: item["retried_at"]
        }
      end

      # Resque's list reads (Resque.peek, Failure.all) return a bare hash
      # (or nil) instead of a list when asked for exactly one item.
      def to_array(items)
        items.is_a?(Array) ? items : [items].compact
      end

      # On redis_multi_queue, count(nil) sums ALL failure queues while
      # all(..., nil) reads the empty default :failed list — pagination
      # over that mismatch reports has_more forever without yielding a
      # record, so a failure queue must be named explicitly.
      def ensure_failure_queue!(queue)
        return unless queue.nil? && multi_queue_failure_backend?
        raise FailureQueueRequiredError.new(@resque::Failure.queues)
      end

      def multi_queue_failure_backend?
        @resque::Failure.backend.name == "Resque::Failure::RedisMultiQueue"
      end

      def ensure_known_queue!(queue)
        known = @resque.queues
        raise UnknownQueueError.new(queue, known) unless known.include?(queue)
      end

      # Greedy to the last "@" — passwords may contain "@", "/", or spaces;
      # over-stripping is acceptable, leaking is not.
      def strip_userinfo(id)
        id.sub(%r{\A(.*?://)?.*@}, '\1')
      end
    end
  end
end
