# resque-mcp

An MCP server for [Resque](https://github.com/resque/resque), mountable as a Rails engine. Lets MCP clients (e.g. Claude Code) inspect queues, workers, and failed jobs — and retry or clear failures — over a single authenticated Streamable HTTP endpoint.

## Requirements

- Ruby >= 3.2
- Rails >= 7.2
- Resque >= 2.7, < 4

## Installation

Not yet published to RubyGems. Until then, install from git:

```ruby
# Gemfile
gem "resque-mcp", github: "jbockler/resque-mcp"
```

## Usage

Mount the engine and configure the auth token:

```ruby
# config/routes.rb
mount Resque::Mcp::Engine => "/resque-mcp"

# config/initializers/resque_mcp.rb
Resque::Mcp.configure do |c|
  c.auth_token = Rails.application.credentials.dig(:resque_mcp, :token)
end
```

The token is **required** — the endpoint answers `503` until one is configured, and `401` on any request without a matching `Authorization: Bearer` header. The engine talks to whatever `Resque.redis` your app already configured; it never opens its own Redis connection.

Connect Claude Code:

```sh
claude mcp add --transport http resque https://your-app.example.com/resque-mcp \
  --header "Authorization: Bearer <token>"
```

Then ask, e.g., "How is my Resque doing?"

## Tools

The tool surface is currently in progress. Every tool response returns structured JSON alongside a text body and ends in a `meta` footer naming the Rails environment and the Redis target (with any credentials stripped), so you always see what you are talking to.

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake` to run the tests and standardrb. You can also run `bin/console` for an interactive prompt.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jbockler/resque-mcp. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jbockler/resque-mcp/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
