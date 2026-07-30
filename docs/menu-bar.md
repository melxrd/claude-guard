# Menu bar (macOS)

`extras/swiftbar/claude-reserve.30s.sh` puts your usage in the menu bar and the
guard's state one glance away.

```
CR 42%          normal
CR 78%          orange — past the first alert level
CR 93%  ⛔      red — the guard is blocking right now
CR 42%  ⊖       grey — a bypass is active, nothing is being guarded
CR ?            no usage data, or claude-reserve is not installed
```

The dropdown carries both windows with countdowns, sessions waiting to resume,
the data source and its age, and four actions: bypass 30 minutes, clear bypass,
resume pending work, refresh now.

**Resume opens a real session.** The menu bar item runs `resume --run
--terminal`, which opens a terminal window with `claude --continue` in the
blocked directory — you clicked it, so you are there to see it. The watcher's
own automatic resume stays headless. See
[auto-resume.md](auto-resume.md#headless-or-in-front-of-you).

**Every action answers back.** The host runs a click with its output discarded,
so each action goes through `claude-reserve menu`, which turns the command's own
reply into a notification — "Bypass active for 30 minutes", "resuming:
/path/to/project". The resume item is only clickable when something is actually
queued; with an empty queue it reads *Nothing to resume* in grey, because an
enabled item that does nothing is indistinguishable from a broken plugin.

It reads the same cache the hooks read — no extra network calls, no second
source of truth.

## Install

You need a host app. [SwiftBar](https://swiftbar.app) and
[xbar](https://xbarapp.com) share the same plugin format; either works.

```bash
brew install --cask swiftbar
open -a SwiftBar
```

**On first launch SwiftBar asks where to keep plugins.** Pick any folder — it
does not have to be the default. Then copy the plugin into whatever you chose:

```bash
cp extras/swiftbar/claude-reserve.30s.sh <your-plugin-folder>/
chmod +x <your-plugin-folder>/claude-reserve.30s.sh
```

Finally, SwiftBar's menu → **Refresh all**.

**Keep the `.30s.` in the filename.** That is not decoration: the host reads the
refresh interval from the name. Rename it to `claude-reserve.sh` and the plugin
runs once and then sits frozen. Use `.10s.` if you want it snappier — it costs
nothing, since the plugin only reads a local file.

## Check it before installing it

The plugin is just a script that prints text. Run it directly to see exactly
what the menu bar would show:

```bash
./extras/swiftbar/claude-reserve.30s.sh
```

The first line is the menu bar; everything after `---` is the dropdown.

## When it looks wrong

**`CR ?`** — the plugin cannot find `claude-reserve`. Either it is not installed
(`./install.sh` from the repo) or `~/.local/bin` is not on the `PATH` the host
app inherits. The plugin already tries `~/.claude/claude-reserve/claude-reserve`
directly, so this usually means the install itself did not happen.

**`CR 0%` with a real percentage in the dropdown** — you are running a version
older than 1.2.1 in `~/.claude/claude-reserve/`. Before 1.2.1 the percentage was
formatted with the shell's locale, so on a system using a comma as decimal
separator `25.0` was rejected. Re-run `./install.sh`; updating the repo alone
does not update the installed copy.

**Updating the repo does not update this.** The plugin runs from the copy in
SwiftBar's folder, against the binary in `~/.claude/claude-reserve/` — neither is
your working tree. After a `git pull`: `./install.sh`, copy the plugin again,
*Refresh all*.

**A click seems to do nothing** — if the item was *Nothing to resume* in grey,
that is the answer: no session was ever blocked, so there is nothing queued.
`claude-reserve pending` says the same thing in words. If a real action produces
no notification either, the installed copy predates 1.2.4 — actions were silent
by construction there. Re-run `./install.sh` and re-copy the plugin.

**Numbers that lag** — the plugin reads the cache, which the watcher refreshes
every 90 seconds. *Refresh now* in the dropdown forces it.

**Nothing appears in the menu bar** — check the file is executable, that the
name still contains `.30s.`, and that it is in the folder SwiftBar actually
uses (its preferences show the path). SwiftBar's *Open plugin folder* removes
the guesswork.
