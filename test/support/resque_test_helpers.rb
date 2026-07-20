# frozen_string_literal: true

require "resque"
require "resque/failure/redis"
require "resque/failure/redis_multi_queue"
require "mock_redis"

# Real resque on in-memory mock_redis; call +reset_resque!+ in setup.
module ResqueTestHelpers
  def reset_resque!
    Resque.redis = MockRedis.new
    Resque::Failure.backend = Resque::Failure::Redis
  end

  def seed_jobs(queue, klass, count: 1, args: [])
    count.times { Resque::Job.create(queue, klass, *args) }
  end

  def seed_worker(*queues, hostname: nil, pid: nil)
    worker = Resque::Worker.new(*queues)
    worker.hostname = hostname if hostname
    worker.pid = pid if pid
    worker.register_worker
    worker
  end

  def start_working(worker, queue: "default", klass: "SomeJob", args: [])
    worker.working_on(Resque::Job.new(queue, {"class" => klass, "args" => args}))
  end

  # Workers that never sent a heartbeat are NOT flagged as expired —
  # only a stale one older than prune_interval is.
  def expire_heartbeat(worker)
    worker.heartbeat!(Time.now - Resque.prune_interval - 60)
  end

  def with_filter_parameters(list)
    original = Resque::Mcp.config.filter_parameters
    Resque::Mcp.config.filter_parameters = list
    yield
  ensure
    Resque::Mcp.config.filter_parameters = original
  end

  # failed_at is an opaque string; rewriting it gives records distinct
  # fingerprints (Failure.create only stamps second granularity).
  def set_failure_failed_at(index, value)
    item = Resque::Failure.all(index, 1)
    item["failed_at"] = value
    Resque.data_store.update_item_in_failed_queue(index, Resque.encode(item))
  end

  # A real failure record via Resque::Failure.create; the exception is
  # raised and rescued so it carries a genuine backtrace.
  def seed_failure(queue: "default", klass: "FailingJob", args: [], message: "boom",
    exception_class: RuntimeError)
    raise exception_class, message
  rescue exception_class => e
    # Failure::Redis#save keeps only frames above the first resque/job.rb
    # frame — without one it stores an empty backtrace, unlike any real
    # failure. Mimic the tail of a genuine job stack.
    e.set_backtrace(e.backtrace + ["/gems/resque/lib/resque/job.rb:283:in 'perform'"])
    Resque::Failure.create(
      payload: {"class" => klass, "args" => args},
      exception: e,
      worker: Resque::Worker.new(queue),
      queue: queue
    )
  end
end
