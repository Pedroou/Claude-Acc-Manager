# claude-profiles

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
| `claude-profiles-sync work-to-personal` \| `personal-to-work` | Copies settings + plugins one way (confirms first, backs up the destination) |

All flags pass through (`claude-personal -r`, `claude -c`, ...). On every
launch you get a yellow warning if the profiles' `settings.json`,
`settings.local.json`, or installed-plugin lists have drifted apart.

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
git clone <this-repo> && cd claude-profiles
./install.fish     # symlinks claude-profiles.fish into ~/.config/fish/conf.d/
exec fish
```

Then set up the two logins (once each):

1. **Default profile**: plain `claude` → `/login` with account #1.
2. **Second profile**: `claude-personal` → `/login` with account #2.
   Tip: don't let `/login` auto-open the browser — copy the URL and paste it
   into the Chrome profile that's logged into the right claude.ai account.
3. **Optional but recommended** — make the second profile inherit all your
   settings, plugins, and session history instead of starting from first-run
   onboarding:

   ```fish
   ./seed-personal.fish
   ```

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
