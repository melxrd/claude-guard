# Data sources

claude-guard needs two numbers: how much of the window you have used, and when
it resets. Three sources are tried in order; the first that answers wins.

## 1. OpenUsage (optional, preferred)

[OpenUsage](https://github.com/robinebers/openusage) is a menu-bar usage tracker
with a local HTTP API:

```bash
curl http://127.0.0.1:6736/v1/usage
```

If you already run it, this is the best source: instant, loopback-only, no rate
limit, no credential handling on our side. claude-guard reads the Claude
provider's session and weekly lines, identified by `periodDurationMs` with the
label as fallback.

`OPENUSAGE_BASE=""` skips it.

## 2. Anthropic OAuth usage endpoint

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <token>
anthropic-beta: oauth-2025-04-20
```

Returns `five_hour` and `seven_day` with `utilization` (0–100) and `resets_at`.
This is the same endpoint OpenUsage uses, which is why claude-guard works
without it.

The token comes from where Claude Code keeps it:

- macOS keychain, service `Claude Code-credentials`
- with a custom `CLAUDE_CONFIG_DIR`, the service gains a suffix:
  `Claude Code-credentials-<sha256(dir)[0:8]>`
- otherwise `~/.claude/.credentials.json`

On macOS the first read may raise a keychain prompt.

**The endpoint is undocumented** and can change without notice. When it does,
claude-guard fails open and logs why.

**It rate-limits hard.** Hence `OAUTH_MIN_INTERVAL=300` — one call every five
minutes at most, whatever the watcher interval. Raise it if you see `429` in the
log.

### No token refresh — on purpose

Access tokens are short-lived. OpenUsage refreshes them via
`POST https://platform.claude.com/v1/oauth/token`. claude-guard does not.

If the server rotates the refresh token during that exchange and the new value
is not written back correctly, the stored credential dies and **you get signed
out of Claude Code**. Not a worthwhile trade for a process running every 90
seconds.

Instead it reads the existing token and, on 401/403, logs:

```
oauth: token rejected (401). It is short-lived; use Claude Code once and it
refreshes itself. claude-guard never rewrites your credentials.
```

You rarely notice, because Claude Code refreshes the token whenever you use it.

## 3. ccusage (estimate)

[ccusage](https://github.com/ryoppippi/ccusage) reads local Claude Code logs:

```bash
ccusage blocks --active --json
```

**This machine only.** If you also use Claude Code elsewhere — another laptop,
the web, Cowork — ccusage cannot see it and will under-report. Treat it as a
floor, not a measurement.

`USE_CCUSAGE=false` skips it.

## When nothing answers

The guard fails open: no blocking, `status` shows the source as `none`, the log
explains why. A `FAIL_BACKOFF` (120s) after a failure keeps every tool call from
paying the connection timeout.

Prefer blocking to being unprotected? `FAIL_MODE=closed` — and remember
`claude-guard bypass` becomes your only way through.

## Caching

Hooks never fetch. They source `~/.claude/usage-guard/usage.env`:

```
FETCHED_EPOCH=1785163914
SESSION_PCT=42.0
SESSION_RESET_EPOCH=1785171113
WEEKLY_PCT=33.0
WEEKLY_RESET_EPOCH=1785671113
SOURCE=oauth
PLAN="Max"
```

The watcher refreshes it every 90 seconds; a hook refreshes inline if it is
older than `CACHE_TTL` (60s), behind a lock and the failure backoff. Older than
`STALE_MAX_SEC` (900s) counts as missing and triggers `FAIL_MODE`.

The raw response is kept in `usage-raw.json` — attach that when reporting a
parsing bug.

## Adding a source

Write `fetch_yourthing()` printing JSON to stdout and returning non-zero when
unavailable, add it to the chain in `_refresh_inner`, and add a branch to the
normaliser keyed on the source name. Both are in `bin/claude-guard`, a few dozen
lines apart. The normaliser prints the variables above, `-1` for unknown.
