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

  def seed_worker(*queues)
    worker = Resque::Worker.new(*queues)
    worker.register_worker
    worker
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
