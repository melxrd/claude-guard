# Configuration

Everything is in `~/.claude/usage-guard/guard.conf`, sourced on every hook call
— **changes apply immediately**, no restart. `config/guard.conf.example` is the
annotated reference; the installer never overwrites an existing config.

```bash
claude-guard status
```

The `decision now` line is your config evaluated against real usage. Fastest way
to check a change did what you meant.

## Blocking

| Setting | Default | Meaning |
|---|---|---|
| `GUARD_ENABLED` | `true` | `false` keeps notifications, drops blocking |
| `SESSION_THRESHOLD` | `90` | % of the 5-hour window above which to block |
| `SESSION_GRACE_MIN` | `30` | Don't block if it resets within this many minutes |
| `WEEKLY_THRESHOLD` | `95` | Same, weekly window |
| `WEEKLY_GRACE_MIN` | `120` | Larger — the last hours of a weekly window are worth spending |

`block if over threshold AND reset is further away than grace`.

**Choosing a threshold.** 90% leaves roughly half an hour of heavy work in
reserve. If you often need a burst at short notice, 80%. Below ~70% the guard
interrupts ordinary work and you will bypass it constantly, which defeats it.

**Which window binds you.** Run `status` a few times over a week. If the weekly
number runs far ahead of the 5-hour one — common on smaller plans — then
`WEEKLY_THRESHOLD` is your real protection. Try 85.

## Fail-safe

| Setting | Default | Meaning |
|---|---|---|
| `FAIL_MODE` | `open` | `open` = allow when data is missing; `closed` = block |
| `STALE_MAX_SEC` | `900` | Cache older than this counts as missing |

`open` is right unless exceeding the limit costs you more than being unable to
work. With `closed`, `claude-guard bypass` is your only way through.

## Notifications

| Setting | Default | Meaning |
|---|---|---|
| `NOTIFY_ON_STOP` | `true` | Notify when a turn finishes |
| `NOTIFY_MIN_TURN_SEC` | `60` | Skip shorter turns |
| `NOTIFY_SOUND` | `Glass` | macOS sound name; `""` for silent |
| `NOTIFY_DEDUPE_SEC` | `300` | Minimum gap between block notifications |
| `ALERT_LEVELS` | `"75 90 95"` | Warn once per window at each |
| `NTFY_TOPIC` | `""` | Phone push topic; empty disables |
| `NTFY_SERVER` | `https://ntfy.sh` | Self-hosted instance goes here |
| `NTFY_PRIORITY` | `default` | Routine priority; blocks are always `high` |

`NOTIFY_MIN_TURN_SEC` is what keeps this from being spam — at 60s you only hear
about things you walked away from. Lower it to 5 while testing, then restore it.

See [notifications.md](notifications.md).

## Resume

See [auto-resume.md](auto-resume.md) — those settings change what an unattended
agent may do.

## Data sources

| Setting | Default | Meaning |
|---|---|---|
| `OPENUSAGE_BASE` | `http://127.0.0.1:6736` | `""` to skip |
| `USE_OAUTH_FALLBACK` | `true` | Query the Anthropic usage endpoint |
| `OAUTH_MIN_INTERVAL` | `300` | Minimum seconds between those queries |
| `USE_CCUSAGE` | `true` | Fall back to local token estimates |
| `CCUSAGE_BIN` | `ccusage` | Path if not on `PATH` |
| `CCUSAGE_TIMEOUT` | `8` | Seconds before a hanging ccusage is killed |
| `OAUTH_USAGE_URL` | Anthropic endpoint | Override only behind a proxy |

Raise `OAUTH_MIN_INTERVAL` if the log shows `429`. See
[data-sources.md](data-sources.md).

## Performance

| Setting | Default | Meaning |
|---|---|---|
| `CACHE_TTL` | `150` | Age at which a hook refreshes the cache inline |
| `FAIL_BACKOFF` | `120` | Quiet period after a failed refresh |

Keep `CACHE_TTL` above the watcher interval (90s). Below it, the cache is stale
by design and hooks end up refreshing inline — the one place a network call is
expensive.

`FAIL_BACKOFF` is a safety belt, not a tuning knob: without it every tool call
pays the connection timeout while a source is down. Measured cost with
everything unreachable: about 50ms per call.

## Testing a change

Lower a threshold below current usage, check `status`, try a tool call in a
session started *after* installation. Stuck? `claude-guard bypass 10`. Restore
the threshold afterwards — leaving it low means being blocked for real.
