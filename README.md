# Claude-Acc-Manager

Run two Claude Code accounts (e.g. a work Team seat and a personal Pro
subscription) side by side, permanently logged in, with zero `/login`
switching. Fish shell only.

## What you get

| Command | What it does |
|---|---|
| `claude-work` | Launches Claude Code with the **default** profile (`~/.claude` + `~/.claude.json`) — stock behavior, untouched |
| `claude-personal` | Launches with a second, fully independent profile (`~/.claude-personal`) via `CLAUDE_CONFIG_DIR` |
| `claude` | Sticky: reuses whichever profile you launched last (falls back to work) |
| `claude-profiles-diff` | Shows how the two profiles' settings/plugins differ |
| `claude-profiles-sync work-to-personal` \| `personal-to-work` | **Forces** a one-way copy of settings + plugins, overriding auto-sync and its guards (confirms first, backs up the destination) |

All flags pass through (`claude-personal -r`, `claude -c`, ...). Config drift
between the profiles is reconciled **automatically on launch** — see below.

## Automatic config sync

On every launch, `settings.json`, `settings.local.json` and the plugin registry
are compared between the two profiles. For each one **the newer mtime wins**,
independently — so an edit made in either profile propagates to the other. It
happens with no prompt; you get one line per file saying which way it went, and
the overwritten file is backed up under the destination's `backups/`.

The `claude-profiles-sync` command remains for forcing a direction by hand.
Set `CLAUDE_PROFILES_NO_AUTOSYNC=1` to disable auto-sync and go back to a plain
drift warning.

## Shared session history

Session/chat history is **100% shared** between the profiles, so `/resume`
lists the same sessions no matter which account you launch:

- `projects/` (session transcripts + per-project memory),
- `file-history/` (checkpoint data for `/rewind`), and
- `history.jsonl` (prompt history)

all live in `~/.claude`; the personal profile holds symlinks to them. The links
are created — merging any existing personal history in first (union, newer file
wins, everything else backed up) — on the first launch after install, and are
self-healing: if anything ever replaces a symlink with a real file or
directory, the next launch merges the strays back and restores the link.

### Why "newest wins" alone is not safe

A profile you have only *logged into* is at first-run defaults: its config is
the newest file on disk while being nearly empty. Naive newest-wins would let
that hollow config overwrite your real one on the very first launch. Two things
prevent it:

**1. The seed gate.** Auto-sync stays completely off — in both directions —
until `~/.claude-personal/.profile-seeded` exists. Only `seed-personal.fish`
creates it, and seeding is inherently work→personal. A profile that has merely
been logged into can never act as a sync source.

**2. Content guards.** mtime decides which file is *newer*; these decide whether
it is *plausible*. The winning file is refused if it:

- is missing or not valid JSON;
- is empty, while the file it would overwrite has real content;
- would drop **more than half** the destination's entries (shrink guard);
- ties on mtime with different content (nothing to break the tie).

Plugins get the same treatment on the registry: an empty or drastically shorter
plugin list can't wipe a populated one. Auto-sync also never *deletes* a file to
mirror an absence — it only ever adds or updates.

The guards inspect content, not identity, so they protect the work profile from
a hollow personal one and vice versa. Anything refused falls back to the old
behavior: a yellow warning telling you to reconcile by hand.

"Work" here just means *whichever account lives in the default `~/.claude`
directory* — on a home PC that may well be your personal account, with the
work account in the secondary profile. The names are labels; pick your own
mapping and stay consistent.

## Requirements

- fish shell (3.2+; uses `$argv[2..]`)
- `jq` and `rsync` (for the divergence check, sync, and seeding)
- Claude Code installed as a real binary on `$PATH`

## Install (new machine)

```fish
git clone <this-repo> && cd Claude-Acc-Manager
./install.fish     # symlinks claude-profiles.fish into ~/.config/fish/conf.d/
exec fish
```

Then set up the two logins (once each):

1. **Default profile**: plain `claude` → `/login` with account #1.
2. **Second profile**: `claude-personal` → `/login` with account #2.
   Tip: don't let `/login` auto-open the browser — copy the URL and paste it
   into the Chrome profile that's logged into the right claude.ai account.
3. **Enable auto-sync** — make the second profile inherit all your settings,
   plugins, and session history instead of starting from first-run onboarding,
   and turn on drift reconciliation. **You don't have to remember where the
   script lives:** once the personal profile is logged in, the next time you run
   `claude` or `claude-personal` you'll be asked

   ```
   Enable auto-sync now? [y/N]
   ```

   Answer `y` and it seeds for you. (Say `n` and it won't ask again until you
   run the script yourself — it locates itself, so `~/Claude-Acc-Manager/seed-personal.fish`
   works from any directory.)

## Browser side

Keep both claude.ai accounts logged in permanently using two Chrome **user
profiles** (avatar menu → Add profile). Each profile is a separate cookie
jar, so there's no logout/auto-relogin fight, ever.

## Gotchas learned the hard way

- **Never set `CLAUDE_CONFIG_DIR=~/.claude`** to mean "the default". Once the
  variable is set, Claude Code expects its state file at
  `$CLAUDE_CONFIG_DIR/.claude.json`, but the default profile keeps it at
  `~/.claude.json` (home root) — so it re-runs first-time onboarding. The
  work launcher therefore runs with the variable explicitly **unset**.
- The plugin registry (`plugins/installed_plugins.json`) stores absolute
  paths; copying it between profiles requires rewriting them (sync/seed
  scripts handle this).
- Anything that launches the `claude` binary directly (IDE extensions,
  scripts) bypasses these fish functions and uses the default profile.
- The divergence check deliberately ignores `.claude.json` and caches —
  they change on every run and would warn constantly.
- Syncing plugins mirrors the whole `plugins/` directory (`rsync --delete`), so
  the destination's plugin checkouts become an exact copy of the source's. That
  keeps the registry and the on-disk checkouts consistent, but it can force
  Claude to re-fetch a plugin cache.
- Sync **backups only keep the plugin registry JSONs**, never the `plugins/`
  cache — that cache is hundreds of MB of git checkouts, and copying it on every
  launch piles up gigabytes fast. The checkouts are re-fetchable; the registry
  is the part you can't recreate.
- Don't cache the profile paths in globals at load time. `conf.d` is sourced
  once with the real `$HOME`, so a cached path silently ignores any later
  `$HOME` — which makes the sync untestable and points it at the wrong dirs.
  The functions derive `$HOME/.claude` on every call for exactly this reason;
  tests must run under `fish --no-config`.
