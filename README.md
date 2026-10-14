<div align="center">

<h1>Acc-Manager</h1>

<p><b>Several Claude Code accounts, one Claude Code.</b></p>

<p>
<img alt="fish 3.7+" src="https://img.shields.io/badge/fish-3.7%2B-4aae47?style=flat-square&labelColor=2d333b">
<a href="https://github.com/Pedroou/claude-profiles/actions/workflows/tests.yml"><img alt="tests" src="https://img.shields.io/github/actions/workflow/status/Pedroou/claude-profiles/tests.yml?branch=main&style=flat-square&label=tests&labelColor=2d333b"></a>
<a href="LICENSE"><img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-blue?style=flat-square&labelColor=2d333b"></a>
</p>

<p>
<a href="#using-it">Using it</a> •
<a href="#what-is-shared">What is shared</a> •
<a href="#install">Install</a> •
<a href="#how-it-works">How it works</a>
</p>

</div>

Claude Code holds one login per config directory. `CLAUDE_CONFIG_DIR` gives
you a second one, along with a second copy of everything else:
CLAUDE.md, skills, plugins, settings, and every past session.
Then `/resume` in one account can't see what you did in the other.

**Acc-Manager** keeps the logins apart and **everything else as one**.
You pick a profile when you start Claude Code, or you don't and
get the one you used last.

## Using it

```fish
claude                         # uses the profile you used last
claude-<profile>               # uses <profile> - and it's now the last used one
claude-<profile> [<args>…]     # works with default claude code args
```

```fish
claude-profiles                     # lists all profiles, its account, and running instances
claude-profiles add <name>          # adds a new profile - run 'claude-<profile>' and '/login' to link to an account
claude-profiles remove <profile>    # removes a profile - shared history and settings survive
claude-profiles rename <old> <new>  # renames a profile
claude-help                         # lists every new command and how to use it
```

```
● work       you@company.com     ~/.claude            2 running
  personal   you@example.com     ~/.claude-personal
```

The `●` is the one plain `claude` opens. Removing a profile only ever loses
its login: anything it still held joins the shared copy, and the rest is set
aside in `~/.claude/backups/`. Profile names tab-complete after `claude`.
`claude profiles …`, `claude <profile>` and `claude help` work too.

## What is shared

| One copy, in `~/.claude` | Each account's own |
|---|---|
| `CLAUDE.md`, rules, skills, agents, commands, output styles, keybindings | The login |
| Plugins and marketplaces | `model`, `effortLevel`, `advisorModel` - what the plan can run |
| Settings: hooks, permissions, enabled plugins, env, status line, everything else | How it logs in and which provider it talks to: `apiKeyHelper`, `forceLogin*`, API keys, base URLs, Bedrock and Vertex settings in `env` |
| Every session, so `/resume` and `/rewind` see them all | Claude Code's state file, caches, the live session list |
| Prompt history, todos, plans | Org-managed settings |

Most of the left column is one directory with a symlink to it from each profile.
`settings.json` can't be, because the right column lives inside it, so each profile
keeps its own and they are **merged before every launch**: a setting changed in one
profile is changed in all of them, and the per-account ones are left alone. To
keep another setting per account, name it: `set -U claude_profiles_own env.MY_VAR`.

Sharing is the point, so it has no off switch: every account sees every
session. If your work transcripts mustn't be readable from your personal
account, keep that account on another machine user instead.

A few things you'd otherwise have to ask:

- **What happens at launch?** Nothing you'll notice. It takes under 20 ms, asks
  nothing, and prints a line only if it actually changed something.
- **A session is open in the other account. Is that a problem?** No. A merged
  settings change reaches it exactly as your own edit to `settings.json` would,
  and every write is atomic. The one thing that waits for a profile to be idle
  is merging in a copy of its history left over from before it was shared, and
  that happens only once.
- **Do I need to restart anything?** No.
- **Does anything move?** Only the first time a profile is shared. Its own
  sessions join the shared ones, so none drop out of `/resume`. Anything else
  it had a copy of, while the shared side had one too, is set aside in
  `~/.claude/backups/` and the line printed says so.
- **How many accounts can I have?** As many as you like. A profile is just a
  `~/.claude-<name>` directory Claude Code has started in.

## Install

Requires **fish 3.7+**, `jq`, `rsync` and Linux with GNU coreutils.

```fish
fisher install Pedroou/claude-profiles
```

Or without [fisher](https://github.com/jorgebucaran/fisher):

```fish
git clone https://github.com/Pedroou/claude-profiles
cd claude-profiles
./install.fish        # links into ~/.config/fish, so 'git pull' is an update
```

Your existing `~/.claude` is the first profile, named `default` until you run
`claude-profiles rename default <new name>`. Add one profile per account:

```fish
claude-profiles add <name>
claude <name>         # then run '/login' to connect it to an account
```

Keep both claude.ai accounts signed in by giving each its own browser profile,
and paste the `/login` link into the right one.

## How it works

Everything with a decision in it is two functions.

**Sharing** (`__claude_profiles_share`) runs for each profile before a launch.
An entry that's already a symlink is left alone. A missing one is linked. A real
copy where the link belongs is moved into `~/.claude` if the shared side has
none. If it has one, session directories are merged, with two `rsync` passes
that between them back up every losing version and only those. Anything else
is set aside in `~/.claude/backups/` rather than guessed about.

**Settings** (`__claude_profiles_merge`) is a three-way merge, the way git
merges branches. The common ancestor is the shared settings as of the last
merge, so any setting that differs from it has been changed. That settles the
direction without anyone saying where a change was made, and changes to
different settings made in different profiles both land. When two profiles
change the same setting, a list is merged as a set, and anything else goes to
the newer file, with the other backed up. So a permission granted in one
profile and another revoked in the other both happen, and so do a hook added
in one and a hook edited in the other.

When no `settings.json` has changed since the last merge, which is nearly
always, the whole thing costs a `stat` per profile.

[`docs/design.md`](docs/design.md) has the full reasoning, including the
latest design choices and decisions.

```fish
fish --no-config test/run.fish        # 181 assertions, four suites
```

Every suite runs the real functions against a throwaway `$HOME`, a stand-in
`claude` and a fake `/proc`, then checks that your real profiles weren't
touched.

## Limitations

- **Anything that runs `claude` without going through fish** (an IDE
  extension, a script) gets the default profile, because the profile is chosen
  by the `claude` function.
- **User-scope MCP servers** (`claude mcp add -s user`) are stored in Claude
  Code's state file, which also holds the login, so they stay per account. A new
  profile starts with a copy of the default's.
- **Linux with GNU coreutils.** Whether a session is running comes from
  `/proc`, and the file handling uses GNU options (`mv -T`, `stat -c`).
- A prompt that is exactly a profile's name (`claude personal`), `help`, or
  `profiles` (alone or followed by one of its commands) is taken by this tool. Any
  other wording reaches Claude Code.
- A `claude-<name>` made by `add` or `rename` appear only in that shell and every
  new one. shells already open only get it after they restart.

## Works with

**[Agent Session Manager](https://github.com/Pedroou/claude-sessions-widget)**,
a Plasma panel widget that shows your Claude Code sessions' status,
includes profiles, and allows you to filter sessions through them.
Its account search finds the profiles **Acc-Manager** makes, but
neither one depends on the other.

## Licence

MIT - see [LICENSE](LICENSE).

<sub>Unofficial, and not affiliated with or endorsed by Anthropic. Claude and
Claude Code are trademarks of Anthropic, PBC.</sub>
