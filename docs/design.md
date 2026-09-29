# Design

**Date:** 2026-09-29
**Status:** Implemented. Installed by `./install.fish` or fisher.

## Goal

Use more than one Claude Code account on one machine - typically a work seat and
a personal subscription - without logging in and out, and without that turning
into more than one Claude Code. The only choice left to the user is which account
to start in, and even that has a default: the one used last.

## Non-goals

- **Switching the account of a running session.** A session belongs to the
  profile it started in.
- **Syncing between machines.** That's a dotfiles job. This is about the
  accounts on one machine.
- **Anything that runs `claude` without the fish function** - IDE extensions,
  scripts. They get the default profile, which is what Claude Code does anyway.

## What a profile is

Claude Code already has the whole mechanism: `CLAUDE_CONFIG_DIR` picks the
directory it keeps everything in, the login included. So a profile is a
directory and nothing more:

- `~/.claude` is the default profile. It runs with `CLAUDE_CONFIG_DIR`
  **unset**, never set to `~/.claude`: once the variable is set, Claude Code
  looks for its state file inside the directory, but the default keeps it
  beside it, at `~/.claude.json`, so it would think it was a first run.
- `~/.claude-<name>` is the profile `<name>`, as long as Claude Code has started
  in it - it holds `.claude.json` or `.credentials.json`. That keeps out
  anything else that happens to be called `~/.claude-something`.

There is no list of profiles to keep in step with the disk. Making the
directory makes the profile; `claude-profiles add` only does it with the
onboarding and folder-trust answers already filled in. The one thing that can't
live in a path is the default's name, which is kept in the state directory.

`claude <name>` starts a profile, and `claude` alone starts the last one.
The name has to be the first argument, so a new profile can't be called after
one of Claude Code's own commands - `add` asks `claude --help` for the list,
so a command added in a later version is caught too. A `CLAUDE_CONFIG_DIR`
already in the environment is respected over the remembered profile, which is
what keeps a copied `CLAUDE_CONFIG_DIR=… claude --resume <id>` meaning what it
says.

## Share, don't sync

The previous version kept two full profiles and a command to copy one onto the
other, with a prompt at launch when they drifted apart. The prompt is the part
that failed: it asked a question the user couldn't answer. Which way should
this go? What happens to the other side? Is it safe with a session open? It
guessed the direction from the last profile used, which is wrong exactly when
it matters. It also compared settings that were per-account by design, so it
fired for no reason.

The fix isn't a better prompt. It's making the question unnecessary: almost
nothing in a profile is actually about the account, and what isn't can be one
copy. One copy can't drift, so there's nothing to sync.

**Shared**, as one directory in `~/.claude` with a symlink to it from each
profile:

| Entry | Why it's shared |
|---|---|
| `CLAUDE.md`, `rules/` | Your instructions. The previous version didn't share these, so the second account quietly ran without them. |
| `skills/`, `agents/`, `commands/`, `output-styles/`, `keybindings.json` | Things you wrote. |
| `plugins/` | Installed once, not per account. Two sessions using one plugin directory is already what happens with two sessions in one account, and it saves a second multi-hundred-megabyte cache. |
| `projects/` | Transcripts and project memory. Shared, `/resume` lists every session from either account. |
| `file-history/` | What `/rewind` restores from. |
| `history.jsonl`, `paste-cache/`, `image-cache/` | Prompt history, and the pasted content its entries point to by hash. Sharing one without the other would leave the up-arrow recalling pastes it can't find. |
| `todos/`, `plans/` | They belong to sessions, which are shared. |

**Its own**: the login (`.credentials.json`), Claude Code's state file
(`.claude.json`: the account, caches and counters), the live session registry
(`sessions/`, which also keeps sessions attributed to the right account for
tools like Agent Session Manager), org-managed settings (`policy-limits.json`,
`remote-settings.json`) and everything else that is a cache or runtime state.
The list of what's shared is explicit, so anything a future Claude Code adds to
the directory stays per-profile until someone decides otherwise. That's the
safe default.

A link, once made, is never touched again. That includes one you pointed
somewhere yourself.

### Joining the shared copy

A profile from before it was shared, or one where something replaced a link
with a real file, has its own copy where the link belongs. If the shared side
has none, it's moved over. A move within a filesystem leaves open files open,
so that's safe even with a session running. If both sides have one, they're
merged. That swaps out files a running session may be holding open, so it
waits until nothing is running in that profile and says so in the meantime.

How they're merged depends on what they are:

- **Directories**: two `rsync --update --backup` passes into one backup
  directory. The first brings over every file that's newer in the profile,
  saving the shared version it replaces. The second runs the other way over
  files both sides have, which saves the profile's version wherever the shared
  one was newer. Between them, every version that lost is in the backup, and
  nothing else is.
- **`history.jsonl`**: it's a log, so both halves are kept. The result is the
  union of the lines, back in time order.
- **Other files**: the newer one is kept and the other backed up, unless
  they're identical.
- **`plugins/`**: mostly a cache Claude Code fetches again, so it isn't merged
  file by file. What's kept is what can't be fetched again without you: the
  registry entries the shared side lacks, with their files moved over and their
  absolute paths rewritten, and plugin data the shared side has no copy of.

"Nothing running" is checked the way Claude Code checks its own session
records: the record's process must exist, and field 22 of `/proc/<pid>/stat`
(the start time) must match the record's `procStart`. That rules out a record
left behind by a killed session whose pid has since been reused.

## settings.json: a three-way merge

`settings.json` is the one thing that can't be a single file. Most of it is
yours (hooks, permissions, enabled plugins, env), but a few keys are the
account's: `model`, `effortLevel` and `advisorModel` depend on what the plan
can run, and `forceLoginMethod`, `forceLoginOrgUUID`, `apiKeyHelper` and a
credential in `env` (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`,
`CLAUDE_CODE_OAUTH_TOKEN`) pin the login. So each profile keeps its own file, and the files are merged before
every launch.

Merging two files needs a direction, and guessing the direction is what sank
the previous version. A three-way merge doesn't need one. The state directory
keeps the shared part of the settings as of the last merge: the common
ancestor. Against that, any setting that differs has been changed, so it goes
to every profile. It doesn't matter where the change was made, because the
ancestor already records what the value was before.

It's done per setting, at any depth. An object is a folder of settings; any
other value, arrays included, is one setting. So a hook added in one profile
and a different hook edited in another are two changes, and both land. The
cases:

| Since the last merge… | Result |
|---|---|
| nobody changed it | kept |
| one profile changed it, or several changed it the same way | the change, everywhere |
| profiles changed it differently, and every version is a list of strings | merged as a set: every addition and every removal survives |
| profiles changed it differently, otherwise | the newer file's version; the other profile's file is backed up first, and a line says which won |

A deletion is a change like any other, and "deleted" and "set to `null`" are
kept apart. Empty objects count as no setting at all, so the `{}` a deletion
leaves behind never reads as a change of its own. Each profile's file is then
edited in place, setting what changed and removing what went, which keeps its
key order and its per-account keys where they were.

Three situations are handled on purpose rather than falling out of the rules:

- **The first merge** has no ancestor, so it starts from nothing, and every
  setting anyone has counts as added. That makes it a union: no profile loses a
  setting to another.
- **A profile with no `settings.json` yet** has no opinion. Reading it as
  "every setting deleted" would wipe everyone else's, so it's simply given the
  shared settings.
- **A `settings.json` that doesn't parse** stops the merge for every profile
  until it's fixed, for the same reason, and says which file it is.

Writes are atomic: a temporary file of the shell's own, then a rename. A
`settings.json` that is a symlink, into a dotfiles repository for instance, is
written through rather than replaced, and it keeps its file mode. A profile
whose file changed between being read and being written is skipped, not
overwritten, because a live session wrote to it. When any profile is skipped,
the common ancestor stays where it was. Moving it on would make that profile's
stale values look like fresh changes on the next launch and undo everyone
else's. Leaving it means the next launch simply finishes the merge.

### Cost

A launch with nothing to merge is the common case, so it's the fast one. The
state directory also records every `settings.json`'s modification time as of
the last merge, to the nanosecond, from a single `stat`. When they all still
match, `jq` never starts. Measured, the whole preparation for a launch is about
10 ms. Nanoseconds matter here: `path mtime` counts whole seconds, and with it
a change saved in the same second as a merge was missed. The test suite caught
that.

## State

`${XDG_STATE_HOME:-~/.local/state}/claude-profiles/`: `last` (the profile
`claude` opens), `default-name`, `settings.json` (the common ancestor) and
`seen` (the modification times). All of it is derived from `$HOME` on every
call rather than cached when fish starts. A cached path ignores a later
`$HOME`, which would make the code untestable and point the tests at the real
profiles.

## Layout

```
functions/
  claude.fish                     the launcher
  claude-profiles.fish            list, add, remove, rename
  __claude_profiles_find.fish     name <-> directory, and the list of profiles
  __claude_profiles_share.fish    the links, and joining the shared copy
  __claude_profiles_merge.fish    the settings merge
  __claude_profiles_running.fish  is anything running in a profile
  __claude_profiles_state.fish    what's remembered between runs
completions/claude-profiles.fish
conf.d/claude-profiles.fish       profile names as completions for `claude`
install.fish                      links all of the above into ~/.config/fish
test/                             four suites and a runner
```

That's the layout fisher expects, so `fisher install` works with no manifest.
fish autoloads each function the first time it's called.

## Extending a launch

`claude` emits `claude_profiles_launch` with the profile's directory just
before starting Claude Code, after sharing and merging. Anything of your own
that should run first is a fish function with `--on-event
claude_profiles_launch`, kept in your own config rather than in this project.

## Testing

`fish --no-config test/run.fish` runs four suites: launch, share, merge and the
command, installer included. Each one runs the real functions against a
throwaway `$HOME` and `$XDG_STATE_HOME`, a stand-in `claude` that records the
profile and arguments it was started with, and a fake `/proc`
(`CLAUDE_PROFILES_PROC`). Each ends with a tripwire. Before anything moves
`$HOME`, it fingerprints the real profiles: which entries exist and of what
kind (so a directory quietly replaced by a link would show), the settings
files, and the state directory. Afterwards it checks that nothing changed.

## Findings from the previous version

Things the redesign fixed without needing a new mechanism, recorded here
because they were invisible from inside the old design:

- **The shared permission allowlist didn't do anything.** It symlinked
  `settings.local.json` between profiles, but Claude Code only reads that file
  inside a project (`<project>/.claude/settings.local.json`), never from the
  config directory. Permission grants were already shared, because they live
  in the project.
- **The plugin-registry path rewrite never ran.** It only handled registry
  entries that were objects, and every entry is an array.
- **The second profile had no CLAUDE.md, skills or rules.** Nothing shared
  them, so every instruction in `~/.claude/CLAUDE.md` silently didn't apply to
  the other account.
