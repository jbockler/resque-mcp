# resque-mcp

[![Gem Version](https://badge.fury.io/rb/resque-mcp.svg)](https://rubygems.org/gems/resque-mcp)

An MCP server for [Resque](https://github.com/resque/resque), mountable as a Rails engine. Lets MCP clients (e.g. Claude Code) inspect queues, workers, and failed jobs — and retry or clear failures — over a single authenticated Streamable HTTP endpoint.

## Requirements

- Ruby >= 3.2
- Rails >= 7.2
- Resque >= 2.7, < 4

## Installation

Add the gem to your application's Gemfile:

```ruby
# Gemfile
gem "resque-mcp"
```

Then run `bundle install`. Or install it yourself with `gem install resque-mcp`.

## Usage

Mount the engine and configure the auth token:

```ruby
# config/routes.rb
mount Resque::Mcp::Engine => "/resque-mcp"

# config/initializers/resque_mcp.rb
Resque::Mcp.configure do |c|
  # token could be created by e.g.: `bin/rails runner 'puts SecureRandom.base58(32)'`
  c.auth_token = Rails.application.credentials.dig(:resque_mcp, :token)

  # Optional: which job-args keys to mask as [FILTERED] in tool responses.
  # Defaults to your app's config.filter_parameters; an explicit list
  # replaces it (merge yourself if you want both):
  # c.filter_parameters = Rails.application.config.filter_parameters + [:iban]
end
```

The token is **required** — the endpoint answers `503` until one is configured, and `401` on any request without a matching `Authorization: Bearer` header. The engine talks to whatever `Resque.redis` your app already configured; it never opens its own Redis connection.

Job arguments shown by any tool are filtered through `ActiveSupport::ParameterFilter` **before** preview/truncation, using your Rails `filter_parameters` by default — the same keys you hide from your logs are hidden from the model. Filters match hash keys (at any depth, same semantics as Rails log filtering, including anchored dot-notation like `/\Acredit_card\.code\z/`); positional scalar args have no key and pass through. Set `c.filter_parameters = []` to disable.

Scope honestly stated: filtering covers **job args only**. Exception messages and backtraces in failure records are shown unfiltered (Rails doesn't scrub those from logs either) — a secret interpolated into an exception message will be visible, so treat error text accordingly.

Connect Claude Code:

```sh
claude mcp add --transport http resque https://your-app.example.com/resque-mcp \
  --header "Authorization: Bearer <token>"
```

Then ask, e.g., "How is my Resque doing?"

## Tools

The tool surface is read-only so far (worker inspection and failure retry/clear are planned). Every tool response returns structured JSON alongside a text body and ends in a `meta` footer naming the Rails environment and the Redis target (with any credentials stripped), so you always see what you are talking to.

### `overview` — read-only

Global Resque health snapshot; takes no parameters.

```json
{
  "pending": 87, "processed": 1093421, "failed": 1342,
  "queues": 6, "workers": 12, "working": 3,
  "queue_sizes": { "default": 3, "mailers": 0, "imports": 84 },
  "meta": { "environment": "production", "redis": "redis://prod-redis:6379/0/resque" }
}
```

- `pending` and `queue_sizes` come from a single snapshot, so `pending` always equals the sum of `queue_sizes`.
- `processed` is Resque's lifetime counter; `failed` is the current number of records in the failed list.
- `workers` counts registered workers, `working` those currently running a job.

### `queue_stats` — read-only

List all queues with sizes, or inspect a single queue. With `queue` and `include_jobs: true` it pages through the queue's pending job payloads:

```json
{
  "queue": "imports", "size": 84,
  "jobs": [
    { "class": "ImportWorker", "args_preview": "[812, \"s3://bucket/batch-7.csv\"]" },
    { "class": "ImportWorker", "args_preview": "[813, \"s3://bucket/batch-8.csv\"]" }
  ],
  "page": { "total": 84, "offset": 0, "limit": 2, "returned": 2, "has_more": true, "next_offset": 2 },
  "meta": { "…": "…" }
}
```

Every paginated response carries this `page` envelope. Limits are capped at 100 — a larger request is clamped and the clamp noted in the response.

### `list_failures` — read-only

Page through failed jobs, newest first, as compact records (truncated error, args preview, no backtrace). Optionally filter by `class_name`.

```json
{
  "failures": [
    {
      "index": 1341, "failed_at": "2026/07/02 08:59:12 UTC",
      "queue": "imports", "class": "ImportWorker",
      "args_preview": "[812, \"s3://bucket/batch-7.csv\"]",
      "exception": "PG::ConnectionBad",
      "error": "could not connect to server: Connection refused… (truncated)",
      "retried_at": null
    }
  ],
  "page": { "total": 1342, "offset": 0, "limit": 20, "returned": 20, "has_more": true, "next_offset": 20 },
  "meta": { "…": "…" }
}
```

- A failure's `index` is its position in the failed list, deliberately not called an `id`: indexes shift when failures are removed, so re-list after any removal.
- Under a `class_name` filter, `next_offset` is a raw scan cursor — continue paging with the returned value, never compute `offset + limit` yourself. Filtered totals cost a full-list scan and are marked `"total_note": "scan"`.

### `get_failure` — read-only

Full detail for one failed job by `index`: complete args, exception, full error, backtrace (capped at 30 frames, with `backtrace_omitted`), and the worker that failed it.

All truncation anywhere in the tool surface is marked in-band (`"… (truncated)"`, `backtrace_omitted`), so a model always knows when it is seeing an excerpt.

### Failure backends

Both failure tools support Resque's `redis_multi_queue` failure backend: pass the failure-queue name as `queue`. On that backend the tools require it and answer with the list of failure queues when it is missing. On the default backend, `queue` can simply be omitted.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake` to run the tests and standardrb. You can also run `bin/console` for an interactive prompt.

To release a new version, update the changelog and the version number in version.rb, commit it, and then run bundle exec rake release, which will create a git tag for the version, push git commits and the created tag, and push the .gem file to rubygems.org.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jbockler/resque-mcp. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jbockler/resque-mcp/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
