# Redesign notes (2026-09-29)

A personal record of the redesign: what was wrong, what changed, and what is
left to do on each machine. Delete this file before the repository goes public.

## What was wrong with the old version

The launch prompt asked a question nobody could answer: which direction to
sync, what happens to the other side, whether it's safe with a session open. It
guessed the direction from the last profile used, which is wrong exactly when it
matters.

Three bugs were also silently doing nothing or the wrong thing:

- **The "shared permission allowlist" symlink did nothing.** Claude Code only
  reads `settings.local.json` inside a project, never from the config
  directory.
- **The plugin-registry path rewrite never ran.** It only handled object
  entries, and every entry is an array.
- **The personal account never saw `~/.claude/CLAUDE.md`, skills or rules.**
  Nothing shared them. The Claude Code binary confirms it reads user memory from
  `<config dir>/CLAUDE.md`.

## The new design

- **One shared copy.** Everything that isn't about the account lives once in
  `~/.claude` and is symlinked from every profile: CLAUDE.md, rules, skills,
  agents, commands, plugins, every session (so `/resume` and `/rewind` see them
  all) and prompt history. One copy can't drift, so there's nothing to sync.
- **A three-way merge for `settings.json`.** It works the way git merges,
  against the last merged state. A change made anywhere goes everywhere, with no
  direction to guess.
  - These stay per account: `model`, `effortLevel`, `advisorModel`, the login
    pins and API keys in `env`.
  - When two profiles change the same setting, lists of permission rules are
    combined. For anything else the newer file wins and the other is backed up.
- **Any number of profiles.** A profile is just a `~/.claude-<name>` directory,
  so there's no registry to keep in step.

## Questions from before, answered

- **What happens at launch?** Nothing you'll notice: about 11 ms, no prompt,
  and a line only if something actually changed.
- **Do I have to restart?** No.
- **What if a session is running in the other profile?** That's fine. The only
  thing that waits for a profile to be idle is a one-time merge of its leftover
  history.
- **Do chats or locations move?** No. `/resume` sees every session from either
  account.
- **How do I add more profiles?** `claude-profiles add <name>`, then
  `claude <name>` and `/login`. It skips onboarding and keeps your trusted
  folders; this was verified against the real binary.

## Using it

- **`claude [profile] [args]`**: starts the last-used profile, or the one named.
- **`claude-profiles`**: lists every profile with its account, what's running,
  and which one plain `claude` opens.
- **`claude-profiles add | remove | rename`**: manage profiles. `remove` only
  loses the login; anything else the profile held joins the shared copy or goes
  to `~/.claude/backups/`.
- **Gone:**
  - `claude-work` and `claude-personal` are now `claude work` and
    `claude personal`.
  - `claude-profiles-diff`, `claude-profiles-sync` and `seed-personal.fish`
    are removed.

## The repository

- **Code:** seven small autoloaded fish functions plus completions, in fisher's
  layout. Install with `fisher install` or `./install.fish`.
- **Tests:** four hermetic suites, 156 assertions (`fish --no-config
  test/run.fish`). Each runs against a throwaway `$HOME`, a stand-in `claude`
  and a fake `/proc`, then checks that the real profiles weren't touched.
- **Also added:** a CI workflow, an MIT licence, a README in the widget's style,
  and `docs/design.md` with the reasoning. The old agent-generated spec docs
  were removed.
- **Review:** an independent review found seven real issues. All are fixed and
  covered by tests. The two most serious:
  - A skipped write could undo a change on the next launch.
  - `remove` could lose settings that hadn't been merged yet.

## Migration on the first machine (already done)

1. **Backup:** everything small went into
   `~/.claude/backups/before-claude-profiles-redesign-20260929.tar.gz`.
2. **Install:** `install.fish` kept the old names (`work` and `personal`).
3. **First launch:** it linked CLAUDE.md, skills, plugins and the caches into
   `personal`, and removed that profile's 700 MB duplicate plugin cache. There
   were no conflicting versions, so nothing needed a backup.

## To do

1. **Log `personal` back in:** run `claude personal`, then `/login`. Its refresh
   token expired on Sep 25, before any of this.
2. **Install the headed-browser check, on every machine.** It's a rule of the
   machine, not part of this tool, so it's now a handler on the
   `claude_profiles_launch` event. Save the code at the bottom of this file as
   `~/.config/fish/conf.d/claude-headed.fish`. Until then, nothing enforces it.
3. **Run `exec fish` in any terminal that was already open.** Those shells still
   have the old functions loaded.
4. **Merge `redesign` into `main`.** The install links into the checkout, so
   don't switch that checkout to a branch without these files before merging.
   On other machines: `git pull`, check out the merged branch, then run
   `./install.fish`. It carries over `work` and `personal` the same way, and the
   first launch says what it merged.
5. **Rename the GitHub repo to `claude-profiles` before making it public.** The
   README's fisher, CI and clone links assume that name. CI hasn't run on
   GitHub yet.

## Known limits

These are also in the README.

- IDE extensions and anything else that runs `claude` outside fish get the
  default profile.
- User-scope MCP servers stay per account.
- Detecting running sessions uses `/proc`, so it only works on Linux.
- A prompt that is exactly a profile's name opens that profile.

## `~/.config/fish/conf.d/claude-headed.fish`

```fish
# Browser automation must stay headed - agents have to be able to see what they
# build. Headless was the default from 2026-08-11 to 2026-09-10 and cost a month
# of blind UI work; this keeps the revert from quietly coming back, the same way
# the commit-msg hook backstops the attribution setting. See ~/.claude/CLAUDE.md.
#
# Runs just before every `claude` launch, on claude-profiles' launch event, so
# the config is clean before the MCP servers read it. Covers every profile's
# settings.json and the plugin cache, which every profile now shares.
# Never blocks a launch. Moved out of Claude-Acc-Manager on 2026-09-29.
function __claude_assert_headed --on-event claude_profiles_launch
    set -l filter 'walk(if type=="object" and (.args|type)=="array" then .args |= map(select((type=="string" and startswith("--headless")) | not)) else . end)'
    set -l fixed

    for s in $HOME/.claude/settings.json $HOME/.claude-*/settings.json
        test -f $s; or continue
        jq -e '.env.PLAYWRIGHT_MCP_HEADLESS' $s >/dev/null 2>&1; or continue
        if jq 'del(.env.PLAYWRIGHT_MCP_HEADLESS) | if .env == {} then del(.env) else . end' $s >$s.tmp 2>/dev/null
            mv $s.tmp $s; and set -a fixed (string replace $HOME/ '~/' $s)
        else
            rm -f $s.tmp
        end
    end

    for m in $HOME/.claude/plugins/cache/*/*/*/.claude-plugin/plugin.json $HOME/.claude/plugins/cache/*/*/*/.mcp.json
        test -f $m; or continue
        set -l want (jq -Sc "$filter" $m 2>/dev/null)
        test -n "$want"; or continue
        test "$want" = (jq -Sc . $m 2>/dev/null); and continue
        if jq "$filter" $m >$m.tmp 2>/dev/null
            mv $m.tmp $m; and set -a fixed (string replace "$HOME/.claude/plugins/cache/" '' $m)
        else
            rm -f $m.tmp
        end
    end

    test (count $fixed) -gt 0; or return 0
    set_color --bold yellow
    echo "⚠  Re-stripped headless browser config: "(string join ', ' $fixed)
    set_color normal
    echo "   Browser automation stays headed - see ~/.claude/CLAUDE.md."
end
```

## Follow-up after the expert review (2026-10-05)

- **One-time sharing is simpler.** When both sides have a copy, session
  directories are still merged. Everything else (CLAUDE.md, skills, history,
  plugins) is set aside in `~/.claude/backups/` instead. This removed about
  100 lines.
- **Plugin paths are fixed on every launch.** Plugin updates made from
  `personal` had recorded six registry paths through `~/.claude-personal/`.
  Each launch now points them back at `~/.claude/plugins/`. This machine is
  already fixed; the old registry is in
  `~/.claude/backups/installed_plugins.before-repoint-20261005.json`.
- **Hooks and other lists merge as sets.** Two changes to the same hook event
  both land instead of conflicting.
- **The per-account list is wider.** It now covers provider and endpoint
  settings, such as base URLs, Bedrock, Vertex and AWS. Add your own with
  `set -U claude_profiles_own env.X`.
- **Requirements are corrected.** It needs fish 3.7+ and GNU coreutils. CI now
  tests on both fish 3 and fish 4.
- **Small fixes.** The list no longer breaks on plain terminals, the test
  tripwire now works in CI, and it handles a symlinked `$HOME`.
