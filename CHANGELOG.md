# Changelog

## [Unreleased]

- `list_failures` tool: page through failed jobs newest-first with compact records (truncated error, args preview, no backtrace); optional `class_name` filter (filtered totals are marked `"total_note": "scan"` and paging must follow the returned `next_offset` cursor).
- `get_failure` tool: full detail for one failed job by list index — complete args (capped at a few KB), exception, backtrace capped at 30 frames with `backtrace_omitted`, worker, retry stamp. Out-of-range indexes answer with the current failure count. On the redis_multi_queue backend both failure tools require an explicit `queue` and answer a dedicated error naming the failure queues when it is missing. Failures are addressed by `index`, not `id` — the position shifts when records are removed.
- `queue_stats` tool: list all queues with sizes, or inspect one queue and page through its pending job payloads (`include_jobs: true`); paginated responses carry a `page` envelope (`total`/`offset`/`limit`/`returned`/`has_more`/`next_offset`), limits above 100 are clamped with an in-band note, and job args are shown as truncated previews.

## [0.1.0]

- Mountable Rails engine serving a stateless MCP Streamable HTTP endpoint (`POST` only; all other verbs answer 405).
- `overview` tool: global Resque health snapshot (pending/processed/failed totals, queue count and sizes, worker counts) with an environment + Redis-target meta footer (Redis credentials stripped).
- Mandatory bearer-token auth: `Resque::Mcp.configure { |c| c.auth_token = … }`; unauthenticated requests get 401 + `WWW-Authenticate: Bearer`, a blank configured token gets 503.
