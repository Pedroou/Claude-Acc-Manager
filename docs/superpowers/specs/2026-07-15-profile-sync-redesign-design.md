# Design: `claude-profiles` v2 — profile config sync redesign

Date: 2026-07-15

## Problem

The launcher runs two Claude Code accounts side by side via separate config
dirs (`~/.claude` = work, `~/.claude-personal` = personal). Commit `17ceffc`
("Add automatic config sync between profiles") replaced the launch-time drift
*warning* with launch-time *newest-wins auto-copy* of `settings.json`,
`settings.local.json`, and the whole `plugins/` directory, gated behind a
`.profile-seeded` marker and a stack of content guards.

It was a mistake, for reasons that only became clear by inspecting the actual
machine state:

1. **`model` is the real churn source.** The only thing differing between the
   two profiles right now is one key: `settings.json.model` (work `opus[1m]`,
   personal `claude-fable-5[1m]`). Different models per account is
   *intentional*. Auto-sync would flip one profile's model to match the other
   on every launch — fighting the user forever. `settings.local.json` is
   currently byte-identical; the plugin set rarely changes.

2. **The plugin copy was catastrophic.** `plugins/` is 1.4 GB (work) / 898 MB
   (personal) and full of *volatile runtime state* — `.in_use` markers named by
   PID, `.orphaned_at` timestamps, differing cached versions. `rsync -a
   --delete` over that tree on every launch copies gigabytes and clobbers the
   other live instance's in-use markers, forcing re-fetches. This is the
   "redundant files / moving around / re-fetching" the user felt.

3. **Launch-time writes race with live instances.** The user frequently runs
   both profiles at once. Overwriting a profile's files while its instance is
   live risks lost writes.

## Core insight

Classify every piece of config into exactly one of three buckets, and the
problem collapses:

| Bucket | Contents | Handling |
|---|---|---|
| **Volatile / per-profile** | `model`, `effortLevel`, `advisorModel`, `tui` | Never compared, never synced. Each profile keeps its own. Removing these from comparison eliminates ~all day-to-day "divergence". |
| **Shared file** | `settings.local.json` (permission allowlist only) | One physical file, symlinked personal → work. Grants propagate automatically. Zero sync, zero churn. Self-healing (§4). |
| **Shared-on-demand** | `settings.json` non-volatile keys (`hooks`, `enabledPlugins`, `permissions`, `skipAutoPermissionPrompt`, `skipWorkflowUsageWarning`) + plugin **registry** (`installed_plugins.json`) | Propagated only by the deliberate sync command. Never on launch. Never the plugin cache. |

Guiding principle: **share what you can, sync only what you must, and ignore
what's meant to differ.** After excluding volatile keys, the "shared surface"
only changes when the user *deliberately* changes it (installs a plugin, adds a
hook, edits a shared setting) — which is rare, so the correct trigger is
on-demand, not every launch.

## Components

All in `claude-profiles.fish` (sourced from `~/.config/fish/conf.d` via the
`install.fish` symlink). Profile dirs are derived from `$HOME` on every call
(never cached in a global at source time) so the code stays testable under
`fish --no-config` with a fake `$HOME`.

### 1. Launchers — `claude`, `claude-work`, `claude-personal`

Unchanged from v1 except for what happens before launch. Ordering matters
(so "last run" in §3 means the *previous* run):

1. **Read** the previous `~/.claude-last-profile` value → `last` (the sync
   source of truth for §3). Do this before overwriting it.
2. Ensure the shared-`settings.local.json` invariant (§4 self-heal) — cheap,
   local, race-free.
3. Compute **shared-surface drift** (§5) — comparison excludes volatile keys and
   the plugin cache.
4. If drifted: print a one-line yellow warning naming what drifted, then the
   `[Y/n]` prompt (§3) with direction `last`→other. If in sync: print nothing.
5. **Record** the current profile to `~/.claude-last-profile`, forward all
   flags, launch.

- **No auto-copy. No `sleep`. No seed-gate. No enable-me prompt.** The only copy
  that ever happens is one you confirm at the prompt (or run by hand). Launch is
  strictly faster than v1's warning path.

Non-interactive shells (`not isatty stdin`) skip the prompt entirely — they may
print the one-line warning but never block.

### 2. `claude-profiles-sync work-to-personal | personal-to-work`

The single deliberate reconcile action. Given an explicit direction (src → dst):

1. **Key-merge `settings.json`**: for each *non-volatile* key present in src,
   write it into dst; leave dst's `model`/`effortLevel`/`advisorModel`/`tui`
   untouched. Implemented as a `jq` merge that drops volatile keys from src and
   overlays the rest onto dst. Volatile keys can therefore never cross profiles,
   in either direction, by construction.
2. **Reconcile the plugin registry**: copy `plugins/installed_plugins.json`
   src → dst, rewriting the absolute `installPath` prefix from src's plugins dir
   to dst's. The 1.4 GB cache is **never** copied; dst's Claude re-fetches any
   missing checkout itself, once. (Also update `enabledPlugins` via the
   settings.json key-merge above.)
3. **Back up** only the small JSONs about to be overwritten
   (`settings.json`, `installed_plugins.json`) under
   `$dst/backups/profile-sync-<stamp>/`. Never the cache.
4. `settings.local.json` is already shared (§4) — nothing to do.
5. Print one line per artifact changed; report the backup path; re-check drift
   and confirm in-sync (on the shared surface).

With no argument: print usage + current shared-surface drift summary, exit 1.

### 3. Launch-time drift prompt (`[Y/n]`, direction = last profile run)

The direction is chosen automatically from **which profile was run last** — the
value of `~/.claude-last-profile` *as it stands before this launch overwrites
it*. The profile you were last working in is almost certainly where you made the
change, so it is the source of truth (src); the other profile is the
destination (dst). Because the direction is unambiguous, the prompt is a simple
default-yes `[Y/n]`, and it always shows the direction so a wrong guess is
visible before you confirm:

```
⚠  Shared config drifted: enabledPlugins, hooks
   Sync work→personal now? [Y/n]
```

- Enter / `y` / anything not starting with `n`: run `claude-profiles-sync`
  src→dst, then continue launching.
- `n`: skip and launch. The full diff stays available via `claude-profiles-diff`,
  and `claude-profiles-sync <dir>` can be run by hand in either direction.

**Timing (matches the user's model):** the current launch is *not yet* recorded
when the prompt appears, so "last run" is genuinely the previous run, never the
one being launched. Order inside the launcher: read previous last-profile →
detect drift → prompt using it as src → **then** record the current profile.
For the sticky `claude` command, "last run" equals the profile being launched
(sticky reuses it), so the default direction is current→other — a sensible
default. If `~/.claude-last-profile` is absent (first ever launch), src defaults
to the profile being launched.

**Known caveat (accepted):** change on work → launch personal → skip → launch
personal again flips "last run" to personal, so a blind Enter would push
personal's older config onto work. The shown direction lets you catch it, and
the sync backs up every file it overwrites (§2.3), so it is recoverable. This is
an accepted trade for the `[Y/n]` simplicity.

### 4. Shared `settings.local.json` + self-heal

**Setup (one-time, done by `install.fish` / a setup step):** merge both
profiles' current permission grants into `~/.claude/settings.local.json`, then
replace `~/.claude-personal/settings.local.json` with a symlink to it. From then
on both accounts read/write one allowlist; an "always allow X" grant on either
profile is visible to the other on its next start. No sync, no churn.

**Self-heal (every launch):** if `~/.claude-personal/settings.local.json` is
found as a *regular file* (i.e. a write replaced the symlink), merge its grants
into the shared work file (union of `permissions.allow`/`deny`/`ask` arrays,
de-duplicated) and restore the symlink. This makes the shared-file bucket
correct regardless of how Claude Code writes:

- **If Claude writes in place** (open + truncate + write): the symlink survives,
  writes land on the shared target, self-heal never triggers — free.
- **If Claude writes atomically** (write tmp + rename over): the rename replaces
  the symlink with a private file; self-heal re-merges and re-links on the next
  launch, losing nothing.

Which one Claude actually does will be **verified empirically during
implementation** (a sandbox test that drives a real settings.local write). If it
turns out to be atomic-rename *and* the user finds self-heal's "propagates on
next launch, not instantly" latency unacceptable, the fallback is to demote
`settings.local.json` to the shared-on-demand bucket (§2) — no redesign needed.

**Concurrency note:** two live instances granting a permission at the same
instant do a read-modify-write of the whole file; last writer wins, so one grant
could be lost. Permission grants are occasional and simultaneous grants rarer;
this is acceptable and no worse than any copy-based scheme.

### 5. Drift detection (`__claude_profile_divergence`, shared by launch + diff)

Compares only the shared surface:

- `settings.json`: compare the object with volatile keys
  (`model`, `effortLevel`, `advisorModel`, `tui`) removed from both sides
  (`jq 'del(.model,.effortLevel,.advisorModel,.tui)'`), so a model/effort/theme
  difference never counts as drift.
- `settings.local.json`: skipped — it's shared, so it can't drift (self-heal
  guarantees this).
- Plugin **registry**: compare the sorted key list of `.plugins` only. The cache
  is never inspected.

Returns the list of drifted artifacts (empty = in sync).

### 6. `claude-profiles-diff`

Unchanged in spirit: human-readable diff of the shared surface. Updated to (a)
diff `settings.json` with volatile keys stripped so noise is hidden, (b) note
`settings.local.json` is shared, (c) diff the plugin registry key list.

## Cleanup / migration

- Working tree already has `claude-profiles.fish` + `seed-personal.fish`
  reverted to the pre-auto-sync blob (`834122f`) so nothing dangerous is live.
- This redesign **rewrites** `claude-profiles.fish`, updates `seed-personal.fish`
  (drop the `.profile-seeded` arming; seeding stays a plain one-time inherit and
  additionally establishes the shared `settings.local.json` symlink), updates
  `README.md`, and **deletes `tests/test-autosync.fish`** (it tests removed
  machinery and hardcodes `/home/pedro`).
- `install.fish` gains the one-time shared-`settings.local.json` setup (idempotent:
  safe to re-run; a no-op once the symlink exists).
- Ships as one new commit on `main` superseding `17ceffc`. History keeps the
  experiment; `main` moves forward.

## Testing

Sandbox tests (`fish --no-config`, fake `$HOME`, real code sourced), plus a
tripwire asserting the real `~/.claude` is byte-identical before/after:

1. Volatile keys never propagate: sync work→personal leaves personal's `model`
   intact; sync personal→work leaves work's `model` intact.
2. Non-volatile keys do propagate (e.g. a new `hooks` entry crosses).
3. Drift detection ignores volatile keys: differing `model`/`tui` alone ⇒ "in
   sync"; a differing `hooks`/`enabledPlugins`/plugin-registry key ⇒ drift.
4. Plugin registry reconcile rewrites `installPath` and never touches the cache
   (assert a sentinel cache file is untouched / not copied).
5. `settings.local.json` self-heal: seed a regular-file state with a grant work
   lacks ⇒ after launch, grant is unioned into the shared file and the symlink
   is restored.
6. Empirical: drive a real `settings.local.json` write (headless claude) against
   a symlinked path in a throwaway config dir to determine in-place vs atomic;
   record the result and confirm §4's chosen path.
7. Non-interactive launch never blocks on the prompt.
8. Direction = last run: with `~/.claude-last-profile` = `work` and drift
   present, the prompt/auto-direction is `work→personal`; = `personal` ⇒
   `personal→work`; absent ⇒ defaults to the profile being launched. The
   current launch's profile is recorded only *after* the prompt (so it is never
   its own source).
9. Tripwire: real `~/.claude` and `~/.claude-personal` untouched by the suite.

## Non-goals

- Sharing or syncing the plugin **cache** (re-fetchable; per-instance markers).
- Syncing `.claude.json`, credentials, session history, or any state caches.
- Any launch-time file copy between profiles.
- A background daemon / watcher. Nothing runs except at launch and on the
  explicit sync command.
