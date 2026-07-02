# frozen_string_literal: true

require "resque"
require "mock_redis"

# Real resque on in-memory mock_redis; call +reset_resque!+ in setup.
module ResqueTestHelpers
  def reset_resque!
    Resque.redis = MockRedis.new
  end

  def seed_jobs(queue, klass, count: 1, args: [])
    count.times { Resque::Job.create(queue, klass, *args) }
  end

  def seed_worker(*queues)
    worker = Resque::Worker.new(*queues)
    worker.register_worker
    worker
  end
end
