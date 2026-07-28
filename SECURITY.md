# Security

## What this tool can reach

claude-guard reads your Claude Code OAuth token. That is not a detail to skim
past, so here is exactly what it does with it and what it never does.

**Network destinations — all three, complete:**

| Destination | When | Why |
|---|---|---|
| `127.0.0.1:6736` | if OpenUsage is running | local usage API, loopback only |
| `api.anthropic.com/api/oauth/usage` | if OpenUsage is not available | your usage, with your token |
| `$NTFY_SERVER` (default `ntfy.sh`) | only if **you** set `NTFY_TOPIC` | phone push; empty by default |

Nothing else. No analytics, no telemetry, no update check, no error reporting.

**Credentials are read, never written.** The token is read from the macOS
keychain (`Claude Code-credentials`) or `~/.claude/.credentials.json` and used
for one GET request. claude-guard does not refresh, rotate or rewrite it — see
[docs/data-sources.md](docs/data-sources.md) for why refreshing was deliberately
left out.

**The token is not exposed in `ps`.** Headers go to curl through a config file
on stdin, not on the command line, because arguments are readable by any local
user.

**State directory is `chmod 700`.** `~/.claude/usage-guard/` holds usage
percentages, blocked prompts and working directory paths. Not credentials, but
not for other accounts on the machine either.

## What it executes

Two places run something you did not type:

**`AUTO_RESUME`** launches `claude --continue` in a directory it recorded when
it blocked you — unattended, spending quota, possibly editing files. Bounded by
`AUTO_RESUME_MAX` and `AUTO_RESUME_MAX_AGE_H`. Set `AUTO_RESUME=false` if that
is not a trade you want; [docs/auto-resume.md](docs/auto-resume.md) is the full
argument for and against.

**Pending records are sourced as shell.** They are written with `printf %q`, so
paths are quoted correctly and cannot inject commands. If you ever hand-edit a
file under `pending/`, that guarantee is yours to keep.

## Trusting the code

This is a young project by one author. The code being clean today says nothing
about what a future commit contains, and `curl | bash` from `main` executes
whatever is there at that moment.

**Pin a release.** Tags are immutable; `main` is not:

```bash
git clone https://github.com/melxrd/claude-guard
cd claude-guard && git checkout v1.0.2
./install.sh --dry-run
./install.sh
```

**Read the diff before upgrading.** For a tool with read access to your
credentials, `git diff v1.0.2..v1.0.3` is a reasonable habit.

**Verify what you install.** Everything lives in one file. `shellcheck
bin/claude-guard` and `./tests/run-tests.sh` both run offline and take seconds.

## The undocumented endpoint

`api.anthropic.com/api/oauth/usage` is not in Anthropic's public API
documentation. It is the endpoint Claude Code uses for its own `/usage` display,
queried here with your credentials for your own data — but it carries no
stability promise and could change or disappear.

If you would rather not rely on it, `USE_OAUTH_FALLBACK=false` and run OpenUsage
instead. The guard works identically.

## Reporting a vulnerability

Open a GitHub issue for anything already public. For something exploitable,
use GitHub's private vulnerability reporting on this repository instead of an
issue, so it can be fixed before it is described in public.
