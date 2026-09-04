# Claude sessions widget — design

**Date:** 2026-09-04
**Status:** Implemented. Lives in `plasmoid/`, installed by `plasmoid/install.fish`.
**Plasmoid id:** `com.claudeaccmanager.claudesessions`

## Goal

You run several Claude Code sessions at once, in different terminals and
different projects. One of them is blocked on a permission prompt while you are
reading another. The widget answers one question from the panel, without you
alt-tabbing through terminals: **is any session waiting on me?** Opening it
answers the follow-up: which one, in which project, and for how long.

## Non-goals

- No usage or cost reporting — that was a different, unbuilt design
  (`2026-07-13-usage-plasmoid-design.md`).
- No control over the sessions. Nothing here starts, stops, focuses or replies to
  a session; it only reports. Raising the right terminal window is genuinely hard
  under Wayland and is not worth a fragile guess.
- No history. A session that has exited is gone from the list, not greyed out.

## Data source

Claude Code already publishes exactly what the widget needs. Every running
session maintains its own record at `<profile-dir>/sessions/<pid>.json` and
rewrites it whenever its state changes:

```json
{
  "pid": 299676,
  "sessionId": "8bc54fbf-…",
  "cwd": "/home/netcomet/Desktop/Personal/Lab2",
  "name": "lab2-76",
  "kind": "interactive",
  "status": "waiting",
  "waitingFor": "input needed",
  "procStart": "1789211",
  "startedAt": 1788540652634,
  "statusUpdatedAt": 1788543329846,
  "version": "2.1.260"
}
```

No hooks, no polling of transcripts, no API calls, no credentials read. The
widget is a reader of a file the tool already writes.

`status` is a closed set of four values, confirmed against the 2.1.260 binary
(`var Ke=["busy","shell","idle","waiting"]`, guarding the field on read):

| `status`  | Shown as  | Means                                              |
|-----------|-----------|----------------------------------------------------|
| `waiting` | Waiting   | Blocked on you — a permission prompt, a dialog, an MCP request. `waitingFor` / `needs` says which. |
| `busy`    | Working   | Claude is running                                  |
| `shell`   | Shell     | The session has handed the terminal to a shell     |
| `idle`    | Done      | Finished; waiting for your next prompt             |

A fifth display state, **unknown**, catches any value a future version invents:
it is counted and listed with the raw status title-cased, never dropped.

### Liveness

A record outlives its session when the process is killed rather than exiting
cleanly, so a record alone does not mean "running". Each one is checked the way
Claude Code checks its own: the process must exist **and** field 22 of
`/proc/<pid>/stat` — the start time in clock ticks — must equal the record's
`procStart`. That second half is what rules out a recycled pid. Field 2 of `stat`
is the executable name in parentheses and may itself contain spaces or `)`, so
the fields are counted from after the *last* `)`.

### Both profiles

`sessions/` is per-profile: `~/.claude/sessions` and
`~/.claude-personal/sessions` are separate directories (unlike `projects/`, which
the profile scripts share via symlink). Both are read, and each session carries
the profile it came from. The profile is only *shown* on a row when the personal
profile actually has a session running — otherwise it is a column of identical
"work" labels.

## Architecture

```
plasmoid/
  install.fish                       # kpackagetool6 --install / --upgrade
  package/
    metadata.json
    contents/
      scripts/claude-sessions        # fish: registry → one JSON document
      code/sessions.js               # pure display logic, no Qt
      ui/main.qml                    # PlasmoidItem: polling, state, colours
      ui/CompactView.qml             # the panel
      ui/FullView.qml                # the popup
      ui/SessionRow.qml              # one session
      ui/Rail.qml                    # one bar
      ui/ConfigGeneral.qml
      config/{main.xml,config.qml}
      icons/claude-sessions.svg
  test/sessions.test.js              # node tests for code/sessions.js
tests/test-widget.fish               # sandbox tests for the collector
```

### The isolation boundary

Two testable units, and a QML layer thin enough to be checked by eye.

**`scripts/claude-sessions`** owns everything about the registry: which
directories to read, which records are live, how a `status` maps to a state and
label, and what order the sessions come in. It prints one document — sessions
already enriched and sorted, plus per-state counts — and nothing else. It is a
useful command on its own (`plasmoid/package/contents/scripts/claude-sessions |
jq`), which is also how it is tested: `tests/test-widget.fish` builds a throwaway
`$HOME` *and* a throwaway `/proc` (via `CLAUDE_SESSIONS_PROC`) and runs the real
script against them.

**`code/sessions.js`** owns everything about presentation that involves a
decision: relative ages, the headline sentence, which state dominates, the rail
length for a state, and the filter/count pair. Plain JavaScript with no Qt
import, so `plasmoid/test/sessions.test.js` loads it under node.

QML does the rest: bind, lay out, and pick colours from the active theme.

### Data flow

1. A `Timer` in `main.qml` fires — every second while the popup is open, every
   `refreshInterval` seconds (default 5) while it is closed.
2. `Plasma5Support.DataSource` (`executable` engine) runs the collector, resolved
   from inside the package with `Qt.resolvedUrl`, so it works whether the widget
   was installed per-user or system-wide.
3. `onNewData` parses stdout into `sessions` / `profiles`, or sets `failure` from
   stderr. A non-zero exit, empty output, or unparseable JSON is a failure state,
   never a silent empty list.
4. The views bind to `shown` (the configured filter applied) and `shownCounts`
   (derived from `shown`, so the header can never contradict the list).

Two subprocesses per refresh (fish + jq), ~70 ms. The collector reads the record
bodies with fish builtins and hands all of them to one `jq`.

## What it looks like

Native first: every colour comes from `Kirigami.Theme` — `neutralTextColor` for
waiting, `highlightColor` for working, `positiveTextColor` for done,
`disabledTextColor` for unknown — so the widget wears whatever theme the panel is
wearing rather than a palette of its own.

The one invented device is the **rail**: a session is a rounded bar, and the same
bar appears in both representations, so the popup reads as the panel opened up.
Bar *length* encodes urgency (waiting 1.0, working 0.72, shell 0.56, done 0.4),
which means colour is never the only channel — the widget still ranks correctly
in a monochrome theme or to a colourblind eye.

**Panel.** The bars side by side, bottom-aligned so they read as a small chart,
with the running total beside them in the colour of the most urgent state
present. Capped at eight bars; past that the number carries it. Nothing running
draws one faint tick — quiet, not broken. Vertical panels stack the bars and grow
them sideways. Middle-click refreshes.

```
▍▎▎▁  4          ← one waiting (full height), two working, one done
```

**Popup.** A heading, then one sentence that answers the question — "1 waiting
for you, 3 working" — and the list, already sorted with anything blocked at the
top and, within a state, the most recently changed first.

```
Claude Code                                    ⟳
1 waiting for you, 3 working
────────────────────────────────────────────────
▎ lab2-76                              Waiting
▎ Lab2 — input needed                       12s

▊ lab2-syn-b9                          Working
▊ lab2-syn                                   4m
```

Clicking a row opens the things you would otherwise dig out of `ps`: full path,
session id, profile, pid, age, version.

**Motion.** Exactly one thing moves on its own: a working session's rail
breathes. Everything else holds still, so the movement means "this one is
running" rather than decorating the widget. It stops when the user has turned
animations off (`Kirigami.Units.longDuration`).

## Error and empty states

| Condition                          | Panel            | Popup                                                    |
|------------------------------------|------------------|-----------------------------------------------------------|
| Nothing running                    | faint tick, no number | "No sessions running" / "Open a terminal and run claude to start one." |
| Before the first result            | faint tick       | nothing — an empty list would be a guess, not an answer   |
| Collector failed / unparseable     | tick in the error colour | "Can't read the session list" + stderr             |
| Personal profile never created     | unaffected       | unaffected; that profile is simply absent from `profiles` |
| A torn or malformed record         | unaffected       | that one record is skipped, the rest still listed         |

## Settings

- **Check every** *n* seconds (1–60, default 5) while the popup is closed. Open,
  it is always one second.
- **Sessions that are done** — off hides `idle` sessions and the counts follow.
- **Highlight the widget when a session is waiting on me** — sets
  `NeedsAttentionStatus`, which makes the widget push itself out of a collapsed
  system tray. On by default; off for anyone who finds that intrusive.

## Risks

- **The registry is a Claude Code internal.** `sessions/<pid>.json` is not
  documented API, and the `status` vocabulary could grow or change. Two things
  contain that: an unrecognised status is displayed rather than dropped, and all
  of the interpretation is in one small fish script with its own test suite.
- **`/proc` is Linux-only.** So is a Plasma panel, so this costs nothing here.
- **Plasma caches applet QML.** After an upgrade the shell has to be restarted
  before the new code loads; `install.fish` says so rather than doing it.
