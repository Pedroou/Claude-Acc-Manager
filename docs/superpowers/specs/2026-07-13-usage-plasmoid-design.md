# Claude usage plasmoid — design

**Date:** 2026-07-13
**Status:** **Design only — never implemented, and not planned.** This document
is kept as a record of the design, not as a description of working software. Its
one surviving artifact is the captured API response at
`docs/superpowers/specs/fixtures/usage-work.json`.
**Planned repo location:** `plasmoid/` — since taken by a different widget, the
session monitor described in `2026-09-04-sessions-widget-design.md`. Anyone
picking this design up would need to pick a new home for it.

## Goal

A Plasma 6 panel widget (plasmoid) that shows, at a glance, how close each of the
two Claude Code profiles (work + personal) is to its usage limits. Collapsed, it
sits in the panel as an icon plus a worst-limit percentage per profile. Clicked,
it opens a popup with one tab per profile, each showing that profile's usage bars,
mirroring what Claude Code's own `/usage` view displays.

## Non-goals

- No auto-refresh of expired OAuth tokens (see Error handling).
- No historical graphs, cost tracking, or per-project token tallies — only the
  plan usage limits (5-hour, weekly, weekly-scoped).
- No configuration UI beyond what a plasmoid gets for free (panel placement).
- Not a general Anthropic API client; it calls exactly one endpoint.

## Data source

The percentages behind `/usage` come from a live authenticated call, confirmed by
inspecting the `claude` 2.1.207 binary and hitting the endpoint directly:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
Content-Type: application/json
```

The bearer token is read per profile from its credentials file:

- Work:     `~/.claude/.credentials.json`
- Personal: `~/.claude-personal/.credentials.json`

at JSON path `.claudeAiOauth.accessToken`. These files are `chmod 600`, owned by
the user; plasmashell runs as the same user, so they are readable. The token is
never logged or written anywhere by this widget.

### Response shape (relevant fields)

A captured real response lives at `docs/superpowers/specs/fixtures/usage-work.json`. The
fields this widget uses:

- `five_hour`  → `{ utilization: <number 0..100>, resets_at: <ISO8601> }`
- `seven_day`  → same shape (weekly, all models)
- `seven_day_opus` / other `seven_day_*` → same shape or `null` when the plan has
  no such scoped limit
- `limits`: array of `{ kind, group, percent, severity, resets_at, scope, is_active }`
  where `kind` ∈ {`session`, `weekly_all`, `weekly_scoped`, ...},
  `severity` ∈ {`normal`, `warning`, ...}, `scope.model.display_name` names a
  scoped limit's model (e.g. "Opus", "Fable").

The `limits[]` array is the primary source: it already carries `percent`,
`severity`, `resets_at`, a human-mappable `kind`, and `is_active`. The top-level
`five_hour`/`seven_day` objects are a fallback if `limits[]` is absent.

## Which bars are shown (per profile tab)

Mirror `/usage`:

1. **Session** — the 5-hour window (`limits[].kind == "session"`, or `five_hour`).
2. **Weekly** — all models (`kind == "weekly_all"`, or `seven_day`).
3. **Weekly (scoped)** — one bar per active scoped weekly limit
   (`kind == "weekly_scoped"` with a non-null `scope`), labeled by
   `scope.model.display_name` (e.g. "Weekly · Opus"). Omitted when none exist or
   the underlying value is `null`.

Bars whose source value is `null` are not rendered.

## Compact (panel) representation

`◎ W 43% · P 18%`

- An icon, then per profile a short label (`W`/`P`) and its **worst active
  limit** percentage.
- "Worst active limit" = the highest `percent` among the limits selected for that
  profile's tab (Section above). If the API marks limits `is_active`, prefer
  active ones; if none are active, fall back to the max across all shown limits.
- Each percentage is colored by severity: the API `severity` field maps to
  green (`normal`) / amber (`warning`) / red (anything higher). Fallback when
  `severity` is missing: <70% green, 70–90% amber, >90% red.
- A profile with no credentials file shows `P —` (not an error).
- A profile whose fetch failed (network/401) shows `P !` in the error color.
- Clicking anywhere toggles the popup.

## Full (popup) representation

- A `TabBar` (Work | Personal) above a `SwipeView`, one page per profile.
- Each page renders its bars via a reusable `UsageBar` component: label, a fill
  bar colored by severity, the percentage, and a "resets in Xh Ym" / "resets in
  Xd" line derived from `resets_at` relative to now.
- Empty / error states occupy the page body in place of bars:
  - No credentials file → "Not logged in — run `claude-personal`."
  - HTTP 401 / token past `expiresAt` → "Token expired — open Claude for this
    profile to refresh."
  - Other fetch failure → "Couldn't reach the usage API" plus the status/reason.
- A manual refresh button (icon) in the popup header re-fetches both profiles.

## Refresh policy

- Fetch both profiles when the popup opens (fresh data when you look).
- Poll every 5 minutes in the background so the panel percentages stay current.
- Fetches are independent per profile: one profile failing or being absent never
  blocks the other.

## Architecture / components

```
plasmoid/
  package/
    metadata.json                 # Plasma 6 manifest (X-Plasma-API-Minimum-Version 6.0)
    contents/
      ui/main.qml                 # PlasmoidItem: compactRepresentation + fullRepresentation, poll Timer
      ui/UsageBar.qml             # one bar: label + fill + percent + reset text
      ui/ProfileTab.qml           # a profile's bars, or its empty/error state
      code/usage.js               # PURE logic, no Qt imports
  test/
    usage.test.js                 # node tests for code/usage.js
    fixtures/usage-work.json      # captured real response
    fixtures/*.json               # crafted edge cases
  install.fish                    # kpackagetool6 --install/--upgrade wrapper
```

### The isolation boundary

All interpretation of the API response lives in `code/usage.js` as pure functions
with **no Qt/QML dependency** — plain ES5-compatible JavaScript:

- `parseUsage(responseObject)` → `{ bars: [ {id, label, percent, severity,
  resetsAt} ], worstPercent, worstSeverity }`
- `severityFor(percent, apiSeverity)` → `"normal"|"warning"|"critical"`
- `resetText(resetsAtISO, nowMs)` → e.g. `"resets in 2h 14m"`

`main.qml` imports this file (`import "code/usage.js" as Usage`) for both the
compact and full views. The same file is `require()`d by `test/usage.test.js`
under Node. The QML layer is deliberately thin: read file → HTTP GET → hand the
parsed JSON to `Usage.parseUsage` → bind results to components. This keeps the
bug-prone part (field selection, worst-limit choice, severity thresholds, reset
math) fully unit-testable without a running Plasma shell.

### Data flow

1. `main.qml` Timer (and popup `onExpandedChanged`) triggers `fetch(profile)`.
2. `fetch` reads `<profileDir>/.credentials.json` via `XMLHttpRequest` on a
   `file://` URL, parses `.claudeAiOauth.accessToken` and `.expiresAt`.
   - Missing file → emit `state = "absent"`.
   - `expiresAt` in the past → emit `state = "expired"` without calling the API.
3. `fetch` issues the HTTPS `XMLHttpRequest` to the usage endpoint.
   - 200 → `Usage.parseUsage(JSON.parse(responseText))`, `state = "ok"`.
   - 401 → `state = "expired"`.
   - other → `state = "error"` with the code.
4. Compact view binds to each profile's `worstPercent`/`worstSeverity`/`state`;
   full view binds each tab to that profile's `bars` or its state message.

QML `XMLHttpRequest` is not subject to browser CORS and can read `file://`
URLs, so no helper process is required.

## Error handling summary

| Condition                        | Compact | Tab body                                   |
|----------------------------------|---------|--------------------------------------------|
| No credentials file              | `P —`   | "Not logged in — run `claude-personal`."   |
| `expiresAt` past, or HTTP 401    | `P !`   | "Token expired — open Claude to refresh."  |
| Network / non-200 (not 401)      | `P !`   | "Couldn't reach the usage API (`<code>`)." |
| 200 but a limit value is null    | normal  | that bar omitted                           |

## Testing

1. **`test/usage.test.js` (node):** the `code/usage.js` pure layer against
   fixtures — the real `usage-work.json` plus crafted cases: a response with an
   active `weekly_scoped` Opus limit, a response with `null` scoped fields, an
   empty `limits[]` falling back to `five_hour`/`seven_day`, and a `severity`
   escalation. Asserts bar selection, labels, worst-percent, severity mapping,
   and `resetText` output for known clock offsets.
2. **Live smoke check:** `curl` the real endpoint with the work token; already
   verified (HTTP 200, 5h=4%, weekly=43%). Re-run as a manual pre-flight.
3. **Manual install test:** `install.fish` → add widget to panel → confirm
   compact shows `W .. P —` (personal absent today), popup opens, tabs switch,
   Work tab renders bars, manual refresh works.

## Install

`plasmoid/install.fish`:

- `kpackagetool6 --type Plasma/Applet --install package` (or `--upgrade` when the
  plasmoid id is already present), targeting
  `~/.local/share/plasma/plasmoids/`.
- Prints how to add it to the panel (right-click panel → Add Widgets → search
  "Claude Usage").
- Optionally, the repo's top-level `install.fish` gains a prompt offering to run
  this after the shell-function install.

Plasmoid id: `com.claudeaccmanager.claudeusage` — named after the project, not
the author, so the widget is installable by anyone without an identity collision.

## Open risks

- **Endpoint stability:** `/api/oauth/usage` and the `oauth-2025-04-20` beta
  header are undocumented internals of Claude Code; a future version could change
  them. The pure `usage.js` layer localizes the response-shape assumptions so a
  change is a small, well-tested edit.
- **Token freshness:** with auto-refresh out of scope, a profile shows "expired"
  between the token's expiry and the next time you launch that profile. Accepted.
