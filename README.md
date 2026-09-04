# Claude-Acc-Manager

Run two Claude Code accounts — say a work Team seat and a personal Pro
subscription — side by side, permanently logged in, with no `/login` switching.
Fish shell only.

Each account gets its own config directory. Session history and the permission
allowlist are *shared* between them, per-account settings like `model` stay
separate, and everything else syncs only when you say so.

## Commands

| Command | What it does |
|---|---|
| `claude-work` | Launches with the **default** profile (`~/.claude` + `~/.claude.json`) — stock behavior, untouched |
| `claude-personal` | Launches with a second, independent profile (`~/.claude-personal`) via `CLAUDE_CONFIG_DIR` |
| `claude` | Sticky: reuses whichever profile you launched last (falls back to work) |
| `claude-profiles-diff` | Shows how the two profiles differ |
| `claude-profiles-sync work-to-personal \| personal-to-work` | Copies the shared settings + plugin registry one way (backs up whatever it overwrites) |

All flags pass through, so `claude-personal -r`, `claude -c`, and friends work
as usual.

## Install

Requires fish 3.2+, `jq`, `rsync`, and the `claude` binary on `$PATH`.

```fish
git clone <this-repo> && cd Claude-Acc-Manager
./install.fish     # symlinks claude-profiles.fish into ~/.config/fish/conf.d/
exec fish
```

Then log in once per account:

1. **Default profile** — run `claude`, then `/login` with account #1.
2. **Second profile** — run `claude-personal`, then `/login` with account #2.
   Don't let `/login` auto-open the browser; copy the URL and paste it into the
   Chrome profile signed in to the right claude.ai account.
3. **Recommended** — run `./seed-personal.fish` so the new profile inherits your
   settings, plugins and onboarding state instead of starting at first-run
   defaults. It keeps the new account's own identity, and `model` stays
   per-profile, so pick that one yourself with `/model`. Safe to re-run: it
   never overwrites a choice the second profile made for itself.

Keep both claude.ai accounts logged in permanently by using two Chrome **user
profiles** (avatar menu → Add profile). Separate cookie jars means no
logout/re-login fight.

## How it works

Every piece of config falls into one of three buckets:

**Per-profile — never compared, never synced.** `model`, `effortLevel`,
`advisorModel` and `tui`. Different models per account is the whole point, so
these are excluded from every comparison. In practice this is what makes the
tool quiet: it's the key that differs most often.

**Shared — one physical file, no syncing at all.** The permission allowlist
(`settings.local.json`) and your session history (`projects/`, `file-history/`,
`history.jsonl`) live in the work profile; the personal profile holds symlinks.
So `/resume` lists the same sessions from either account, and an "always allow
X" grant on one side is immediately visible to the other.

The links are self-healing: the first launch after install merges any existing
personal-side data in (union, newer file wins, anything overwritten is backed
up) and creates the link. If something ever replaces a symlink with a real file,
the next launch merges the stray back and restores it.

**On demand — synced only when you confirm.** The rest of `settings.json`
(hooks, permissions, enabled plugins) and the plugin **registry**. If these
drift, a launch prints a warning and offers to reconcile:

```
⚠  Shared config drifted: settings.json, plugins
   Sync work→personal now? [Y/n]
```

The direction comes from whichever profile you ran *last* — that's where you
most likely made the change. It's always shown, so a wrong guess is visible
before you confirm, and every overwritten file is backed up under the
destination's `backups/`. Press `n` to skip; `claude-profiles-sync` runs it by
hand later. Non-interactive shells print the warning but never block.

The plugin **cache** is never copied — it's gigabytes of re-fetchable git
checkouts, and it holds per-instance state that breaks when clobbered. Only the
registry moves; the destination re-fetches what it's missing.

<details>
<summary><b>Gotchas learned the hard way</b></summary>

- **Never set `CLAUDE_CONFIG_DIR=~/.claude`** to mean "the default". Once the
  variable is set, Claude Code expects its state file at
  `$CLAUDE_CONFIG_DIR/.claude.json`, but the default profile keeps it at
  `~/.claude.json` (home root) — so it re-runs first-time onboarding. The work
  launcher therefore runs with the variable explicitly **unset**.
- The plugin registry stores absolute paths, so copying it between profiles
  requires rewriting them. The sync does this.
- Anything that launches the `claude` binary directly (IDE extensions, scripts)
  bypasses these fish functions and uses the default profile.
- `.claude.json` and the state caches are deliberately never compared — they
  change on every run and would warn constantly.
- Don't cache the profile paths in globals at load time. `conf.d` is sourced
  once with the real `$HOME`, so a cached path silently ignores any later
  `$HOME` — which makes the sync untestable and points it at the wrong
  directories. The functions derive `$HOME/.claude` on every call for exactly
  this reason, and tests must run under `fish --no-config`.

</details>

## Panel widget

A Plasma 6 widget that shows what every running Claude Code session is doing —
across both profiles — so you can tell from the panel whether one of them is
blocked on you.

Needs Plasma 6 and `kpackagetool6` on top of the requirements above.

```fish
./plasmoid/install.fish     # then: right-click the panel → Add Widgets → "Claude Sessions"
```

Each session is a bar: tallest and amber when it is **waiting** on you, then
**working**, **shell**, and **done** (finished, ready for your next prompt). The
panel shows the bars plus a running total; the popup lists the sessions with
anything blocked at the top, says what it is blocked on, and how long it has been
that way. Clicking a row shows its folder, session id, pid and version.

It reads the registry Claude Code already keeps at
`<profile>/sessions/<pid>.json` — no hooks, no API calls, no credentials — and
checks each record against `/proc` so a session that was killed rather than
closed doesn't linger in the list. The collector is a plain command, useful on
its own:

```fish
./plasmoid/package/contents/scripts/claude-sessions | jq
```

Upgrading the widget while it's already on the panel needs a shell restart —
Plasma caches applet QML. `install.fish` prints the command.

## Notes

"Work" just means *whichever account lives in the default `~/.claude`
directory* — on a home machine that may well be your personal account, with the
work account in the secondary profile. The names are labels; pick your own
mapping and stay consistent.

## Design docs

`docs/superpowers/specs/` holds the design write-ups — the profile-sync
redesign explains why launch-time auto-copying was removed in favour of the
three buckets above, and the sessions-widget document covers the panel widget,
including why the session registry is the right thing to read. The
usage-plasmoid document is a **design only**; that widget was never built and
isn't planned.

## Tests

```fish
fish --no-config tests/test-profiles.fish
fish --no-config tests/test-sessions.fish
fish --no-config tests/test-seed.fish
fish --no-config tests/test-widget.fish
```

Each suite builds a throwaway `$HOME`, runs the real code against it, and
asserts your actual `~/.claude` was untouched. The widget suite builds a
throwaway `/proc` too, so it can test what happens to a record whose process is
gone or whose pid has been recycled.

The widget's display logic is plain JavaScript with no Qt dependency, so it is
tested under node:

```fish
node --test plasmoid/test/sessions.test.js
```
