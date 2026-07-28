# Contributing

## Before a pull request

```bash
./tests/run-tests.sh
shellcheck -S warning bin/claude-reserve install.sh tests/run-tests.sh
```

Both must pass. CI runs them on macOS and Ubuntu.

## Ground rules

**The guard must never be the thing that stops you working.** When in doubt,
fail open and log the reason. A false block costs the user real time and trust;
a missed block costs some quota.

**Every block explains itself and how to undo it.** If you add a blocking
condition, the message must say what tripped, by how much, and the command to
override.

**No synchronous network calls in hooks.** They run on every tool call. Fetching
belongs in the watcher, behind the cache and the failure backoff.

**Keep it dependency-free.** bash, curl and python3 are the whole toolchain, and
python3 is only used for JSON parsing. Please do not add a runtime.

## Adding a usage source

1. Write `fetch_yourthing()` — print JSON to stdout, return non-zero when
   unavailable.
2. Add it to the chain in `_refresh_inner()`.
3. Add a branch to the normaliser keyed on the source name, printing the
   variables documented in `docs/data-sources.md` (`-1` for unknown).
4. Add a test with a fake server, following the pattern in section 3 of
   `tests/run-tests.sh`.

## Reporting a bug

For a wrong percentage, attach `~/.claude/claude-reserve/usage-raw.json` — that is
the raw response the parser saw, and it is usually enough to find the problem.
For a block that should not have happened, attach the relevant lines of
`reserve.log` and the output of `claude-reserve status`.
