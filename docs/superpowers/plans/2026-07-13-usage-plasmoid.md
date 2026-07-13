# Claude Usage Plasmoid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Plasma 6 panel widget showing both Claude Code profiles' usage-limit percentages, expanding on click to a tab-per-profile popup of usage bars.

**Architecture:** All response interpretation lives in one Qt-free JavaScript file (`code/usage.js`) that is unit-tested under Node and imported by QML. The QML layer is thin: read each profile's token from its `.credentials.json`, GET `/api/oauth/usage`, hand the JSON to `usage.js`, bind the result to a compact (panel) and full (popup) representation.

**Tech Stack:** Plasma 6 / Qt 6 QML (`org.kde.plasma.plasmoid`, Kirigami, PlasmaComponents3), plain ES5 JavaScript, Node 22 built-in test runner, `kpackagetool6`, fish.

## Global Constraints

- Target Plasma 6: `metadata.json` sets `"X-Plasma-API-Minimum-Version": "6.0"`, `"KPackageStructure": "Plasma/Applet"`.
- Plasmoid id (verbatim): `com.pedroou.claudeusage`.
- Usage endpoint (verbatim): `GET https://api.anthropic.com/api/oauth/usage`.
- Required request headers (verbatim): `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `Content-Type: application/json`.
- Token source per profile: JSON path `.claudeAiOauth.accessToken` (and `.claudeAiOauth.expiresAt`, epoch milliseconds) in `~/.claude/.credentials.json` (work) and `~/.claude-personal/.credentials.json` (personal).
- `code/usage.js` MUST have no Qt/QML imports and MUST be `require()`-able under Node (dual-mode export) so the same file runs in tests and in QML.
- The bearer token MUST NOT be logged, printed, or written anywhere by the widget.
- Bars whose source percentage is `null` are never rendered.
- Severity → color: `normal` = green, `warning` = amber, `critical` = red, using Kirigami theme colors (`positiveTextColor` / `neutralTextColor` / `negativeTextColor`).
- All code lives under `plasmoid/` in the Claude-Acc-Manager repo.

---

## Task 0: Dev-loop tooling (optional but recommended)

**Files:** none (system package).

Installs `plasmoidviewer` so QML tasks (4–6) can be run without touching your live panel. If you skip this, use the plasmashell-restart fallback noted in those tasks.

- [ ] **Step 1: Install plasma-sdk**

Run: `sudo dnf install -y plasma-sdk`
Expected: `plasmoidviewer` now on `$PATH` (`command -v plasmoidviewer` prints a path).

- [ ] **Step 2: Verify**

Run: `plasmoidviewer --version`
Expected: prints a version line, exits 0.

---

## Task 1: Scaffold + `severityFor`

**Files:**
- Create: `plasmoid/package/contents/code/usage.js`
- Create: `plasmoid/test/usage.test.js`

**Interfaces:**
- Produces: `severityFor(percent: number, apiSeverity: string|null|undefined) → "normal"|"warning"|"critical"`. Exported on `module.exports` for Node.

- [ ] **Step 1: Write the failing test**

Create `plasmoid/test/usage.test.js`:

```javascript
const test = require("node:test");
const assert = require("node:assert");
const U = require("../package/contents/code/usage.js");

test("severityFor: API severity wins over percent", () => {
  assert.equal(U.severityFor(5, "warning"), "warning");
  assert.equal(U.severityFor(99, "normal"), "normal");
  assert.equal(U.severityFor(10, "critical"), "critical");
  assert.equal(U.severityFor(10, "severe"), "critical"); // unknown → critical
});

test("severityFor: percent fallback when no API severity", () => {
  assert.equal(U.severityFor(10, null), "normal");
  assert.equal(U.severityFor(69, null), "normal");
  assert.equal(U.severityFor(70, null), "warning");
  assert.equal(U.severityFor(90, null), "warning");
  assert.equal(U.severityFor(91, null), "critical");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test plasmoid/test/usage.test.js`
Expected: FAIL — `Cannot find module '../package/contents/code/usage.js'`.

- [ ] **Step 3: Write minimal implementation**

Create `plasmoid/package/contents/code/usage.js`:

```javascript
// Pure, Qt-free logic for the Claude usage plasmoid.
// Imported by QML (import "code/usage.js" as Usage) AND require()'d by Node tests.

function severityFor(percent, apiSeverity) {
    if (apiSeverity) {
        if (apiSeverity === "normal") return "normal";
        if (apiSeverity === "warning") return "warning";
        return "critical";
    }
    if (percent > 90) return "critical";
    if (percent >= 70) return "warning";
    return "normal";
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { severityFor: severityFor };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test plasmoid/test/usage.test.js`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add plasmoid/package/contents/code/usage.js plasmoid/test/usage.test.js
git commit -m "feat(plasmoid): add severityFor usage logic"
```

---

## Task 2: `resetText`

**Files:**
- Modify: `plasmoid/package/contents/code/usage.js`
- Modify: `plasmoid/test/usage.test.js`

**Interfaces:**
- Produces: `resetText(resetsAtISO: string|null, nowMs: number) → string` (e.g. `"resets in 2h 14m"`, `"resets in 3d"`, `"resets in 40m"`, `"resets now"`, `""` when input is empty/invalid).

- [ ] **Step 1: Write the failing test**

Append to `plasmoid/test/usage.test.js`:

```javascript
test("resetText: formats future offsets", () => {
  const now = Date.parse("2026-07-13T00:00:00Z");
  const iso = (ms) => new Date(now + ms).toISOString();
  assert.equal(U.resetText(iso(134 * 60000), now), "resets in 2h 14m");
  assert.equal(U.resetText(iso(3 * 1440 * 60000), now), "resets in 3d");
  assert.equal(U.resetText(iso(40 * 60000), now), "resets in 40m");
  assert.equal(U.resetText(iso(-5000), now), "resets now");
  assert.equal(U.resetText(null, now), "");
  assert.equal(U.resetText("not-a-date", now), "");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test plasmoid/test/usage.test.js`
Expected: FAIL — `U.resetText is not a function`.

- [ ] **Step 3: Write minimal implementation**

In `plasmoid/package/contents/code/usage.js`, add before the export block:

```javascript
function resetText(resetsAtISO, nowMs) {
    if (!resetsAtISO) return "";
    var t = Date.parse(resetsAtISO);
    if (isNaN(t)) return "";
    var diff = t - nowMs;
    if (diff <= 0) return "resets now";
    var totalMin = Math.floor(diff / 60000);
    var days = Math.floor(totalMin / 1440);
    if (days >= 1) return "resets in " + days + "d";
    var hours = Math.floor(totalMin / 60);
    var mins = totalMin % 60;
    if (hours >= 1) return "resets in " + hours + "h " + mins + "m";
    return "resets in " + mins + "m";
}
```

And update the export block to:

```javascript
if (typeof module !== "undefined" && module.exports) {
    module.exports = { severityFor: severityFor, resetText: resetText };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test plasmoid/test/usage.test.js`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add plasmoid/package/contents/code/usage.js plasmoid/test/usage.test.js
git commit -m "feat(plasmoid): add resetText relative-time formatting"
```

---

## Task 3: `selectBars` + `parseUsage` (with fixtures)

**Files:**
- Modify: `plasmoid/package/contents/code/usage.js`
- Modify: `plasmoid/test/usage.test.js`
- Create: `plasmoid/test/fixtures/usage-scoped.json`
- Create: `plasmoid/test/fixtures/usage-fallback.json`
- Exists already: `plasmoid/test/fixtures/usage-work.json` (captured real response)

**Interfaces:**
- Produces:
  - `labelForKind(limit) → string`
  - `barFromWindow(id, label, window) → bar`
  - `selectBars(response) → Array<{id, label, percent, severity, resetsAt}>`
  - `parseUsage(response) → { bars, worstPercent, worstSeverity }`
- A `bar` is `{ id: string, label: string, percent: number, severity: "normal"|"warning"|"critical", resetsAt: string|null }`.
- Selection rules: include `limits[]` entries with `kind==="session"` and `kind==="weekly_all"` always; include `kind==="weekly_scoped"` only when `is_active===true`. When `limits[]` is absent/empty, fall back to top-level `five_hour`, `seven_day`, and `seven_day_opus` (the last only when non-null).

- [ ] **Step 1: Create the crafted fixtures**

Create `plasmoid/test/fixtures/usage-scoped.json` (active scoped Opus limit present):

```json
{
  "limits": [
    { "kind": "session", "group": "session", "percent": 12, "severity": "normal", "resets_at": "2026-07-13T05:00:00+00:00", "scope": null, "is_active": true },
    { "kind": "weekly_all", "group": "weekly", "percent": 55, "severity": "warning", "resets_at": "2026-07-16T16:00:00+00:00", "scope": null, "is_active": true },
    { "kind": "weekly_scoped", "group": "weekly", "percent": 88, "severity": "warning", "resets_at": "2026-07-16T16:00:00+00:00", "scope": { "model": { "id": null, "display_name": "Opus" }, "surface": null }, "is_active": true },
    { "kind": "weekly_scoped", "group": "weekly", "percent": 2, "severity": "normal", "resets_at": "2026-07-16T16:00:00+00:00", "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": false }
  ]
}
```

Create `plasmoid/test/fixtures/usage-fallback.json` (no `limits[]`; top-level windows only):

```json
{
  "five_hour": { "utilization": 20, "resets_at": "2026-07-13T05:00:00+00:00" },
  "seven_day": { "utilization": 60, "resets_at": "2026-07-16T16:00:00+00:00" },
  "seven_day_opus": { "utilization": 95, "resets_at": "2026-07-16T16:00:00+00:00" },
  "seven_day_sonnet": null,
  "limits": []
}
```

- [ ] **Step 2: Write the failing tests**

Append to `plasmoid/test/usage.test.js`:

```javascript
const fs = require("node:fs");
const path = require("node:path");
const fx = (name) => JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8"));

test("selectBars: real work response → session + weekly, scoped omitted (inactive)", () => {
  const bars = U.selectBars(fx("usage-work.json"));
  assert.deepEqual(bars.map((b) => b.label), ["Session (5h)", "Weekly"]);
  assert.equal(bars.find((b) => b.label === "Weekly").percent, 43);
});

test("selectBars: active scoped limit is included and labeled by model", () => {
  const bars = U.selectBars(fx("usage-scoped.json"));
  assert.deepEqual(bars.map((b) => b.label), ["Session (5h)", "Weekly", "Weekly · Opus"]);
  assert.equal(bars.find((b) => b.label === "Weekly · Opus").percent, 88);
  // the inactive Fable scoped limit must be dropped
  assert.equal(bars.some((b) => b.label.indexOf("Fable") !== -1), false);
});

test("selectBars: falls back to top-level windows when limits[] empty", () => {
  const bars = U.selectBars(fx("usage-fallback.json"));
  assert.deepEqual(bars.map((b) => b.label), ["Session (5h)", "Weekly", "Weekly · Opus"]);
  assert.equal(bars.find((b) => b.label === "Weekly · Opus").percent, 95);
});

test("parseUsage: worst is the highest-percent bar with its severity", () => {
  const r = U.parseUsage(fx("usage-scoped.json"));
  assert.equal(r.worstPercent, 88);
  assert.equal(r.worstSeverity, "warning");
});

test("parseUsage: empty response yields no bars, zero worst", () => {
  const r = U.parseUsage({});
  assert.deepEqual(r.bars, []);
  assert.equal(r.worstPercent, 0);
  assert.equal(r.worstSeverity, "normal");
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `node --test plasmoid/test/usage.test.js`
Expected: FAIL — `U.selectBars is not a function`.

- [ ] **Step 4: Write minimal implementation**

In `plasmoid/package/contents/code/usage.js`, add before the export block:

```javascript
function labelForKind(limit) {
    if (limit.kind === "session") return "Session (5h)";
    if (limit.kind === "weekly_all") return "Weekly";
    if (limit.kind === "weekly_scoped") {
        var m = limit.scope && limit.scope.model && limit.scope.model.display_name;
        return m ? ("Weekly · " + m) : "Weekly (scoped)";
    }
    return limit.kind;
}

function barFromWindow(id, label, w) {
    return {
        id: id,
        label: label,
        percent: w.utilization,
        severity: severityFor(w.utilization, null),
        resetsAt: w.resets_at || null
    };
}

function selectBars(resp) {
    var bars = [];
    if (resp && resp.limits && resp.limits.length) {
        for (var i = 0; i < resp.limits.length; i++) {
            var L = resp.limits[i];
            var include = (L.kind === "session") || (L.kind === "weekly_all") ||
                          (L.kind === "weekly_scoped" && L.is_active === true);
            if (!include) continue;
            var scopedName = (L.scope && L.scope.model && L.scope.model.display_name) || "";
            bars.push({
                id: L.kind + (scopedName ? ":" + scopedName : ""),
                label: labelForKind(L),
                percent: L.percent,
                severity: severityFor(L.percent, L.severity),
                resetsAt: L.resets_at || null
            });
        }
        return bars;
    }
    if (resp && resp.five_hour) bars.push(barFromWindow("session", "Session (5h)", resp.five_hour));
    if (resp && resp.seven_day) bars.push(barFromWindow("weekly_all", "Weekly", resp.seven_day));
    if (resp && resp.seven_day_opus) bars.push(barFromWindow("weekly_scoped:Opus", "Weekly · Opus", resp.seven_day_opus));
    return bars;
}

function parseUsage(resp) {
    var bars = selectBars(resp);
    var worstPercent = 0, worstSeverity = "normal";
    for (var i = 0; i < bars.length; i++) {
        if (bars[i].percent > worstPercent) {
            worstPercent = bars[i].percent;
            worstSeverity = bars[i].severity;
        }
    }
    return { bars: bars, worstPercent: worstPercent, worstSeverity: worstSeverity };
}
```

Update the export block to:

```javascript
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        severityFor: severityFor,
        resetText: resetText,
        labelForKind: labelForKind,
        barFromWindow: barFromWindow,
        selectBars: selectBars,
        parseUsage: parseUsage
    };
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `node --test plasmoid/test/usage.test.js`
Expected: PASS (8 tests total).

- [ ] **Step 6: Commit**

```bash
git add plasmoid/package/contents/code/usage.js plasmoid/test/usage.test.js plasmoid/test/fixtures/usage-scoped.json plasmoid/test/fixtures/usage-fallback.json
git commit -m "feat(plasmoid): add bar selection and parseUsage with fixtures"
```

---

## Task 4: Plasmoid manifest + installable compact shell

**Files:**
- Create: `plasmoid/package/metadata.json`
- Create: `plasmoid/package/contents/ui/main.qml`
- Create: `plasmoid/install.fish`

**Interfaces:**
- Produces: an installable plasmoid with id `com.pedroou.claudeusage` whose compact representation renders a static `◎ W --% · P --%` and toggles `expanded` on click, and a placeholder full representation. Later tasks replace the placeholder bindings with live data.

- [ ] **Step 1: Write the manifest**

Create `plasmoid/package/metadata.json`:

```json
{
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API-Minimum-Version": "6.0",
    "KPlugin": {
        "Id": "com.pedroou.claudeusage",
        "Name": "Claude Usage",
        "Description": "Usage-limit bars for two Claude Code profiles",
        "Icon": "help-about",
        "Authors": [{ "Name": "Pedroou", "Email": "pedro.g.ourique@gmail.com" }],
        "Category": "System Information",
        "License": "MIT",
        "Version": "0.1.0"
    }
}
```

- [ ] **Step 2: Write the install helper**

Create `plasmoid/install.fish`:

```fish
#!/usr/bin/env fish
# Installs (or upgrades) the Claude Usage plasmoid into the user's Plasma.
set -l repo (dirname (realpath (status filename)))
set -l pkg $repo/package
set -l id com.pedroou.claudeusage

if kpackagetool6 --type Plasma/Applet --show $id >/dev/null 2>&1
    kpackagetool6 --type Plasma/Applet --upgrade $pkg
else
    kpackagetool6 --type Plasma/Applet --install $pkg
end
and echo "Installed $id. Add it via: right-click your panel → Add Widgets → search \"Claude Usage\"."
```

- [ ] **Step 3: Write the compact shell**

Create `plasmoid/package/contents/ui/main.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        implicitWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "help-about"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PlasmaComponents3.Label { text: "W --%" }
            PlasmaComponents3.Label { text: "·"; opacity: 0.6 }
            PlasmaComponents3.Label { text: "P --%" }
        }
    }

    fullRepresentation: PlasmaComponents3.Label {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "Claude Usage — popup placeholder"
    }
}
```

- [ ] **Step 4: Install and verify it loads**

Run: `fish plasmoid/install.fish`
Expected: prints `Installed com.pedroou.claudeusage.`

Then run it in isolation (Task 0 tooling):
Run: `plasmoidviewer -a com.pedroou.claudeusage`
Expected: a window showing `◎ W --% · P --%`; clicking it opens the placeholder popup.

Fallback if `plasmoidviewer` is not installed: add the widget to your panel, then reload with `systemctl --user restart plasma-plasmashell` (Wayland) and confirm visually.

- [ ] **Step 5: Commit**

```bash
git add plasmoid/package/metadata.json plasmoid/package/contents/ui/main.qml plasmoid/install.fish
git commit -m "feat(plasmoid): installable compact shell + install.fish"
```

---

## Task 5: Live fetch wired to the compact view

**Files:**
- Modify: `plasmoid/package/contents/ui/main.qml`

**Interfaces:**
- Consumes: `code/usage.js` (`parseUsage`) via `import "../code/usage.js" as Usage`.
- Produces: two profile state objects `workProfile` / `personalProfile`, each a `QtObject` with properties `label` (string), `dir` (string), `state` (`"loading"|"ok"|"absent"|"expired"|"error"`), `errorCode` (string), `bars` (var array), `worstPercent` (real), `worstSeverity` (string); a function `fetchProfile(profile)`; a function `fetchAll()`; and a compact view bound to each profile's `state`/`worstPercent`/`worstSeverity`.

- [ ] **Step 1: Add profile state, fetch logic, and a color helper**

Replace the entire contents of `plasmoid/package/contents/ui/main.qml` with:

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid
import Qt.labs.platform as Platform
import "../code/usage.js" as Usage

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    // Resolve $HOME portably. Qt.labs.platform ships with Qt 6 (module verified
    // present at /usr/lib64/qt6/qml/Qt/labs/platform). If a future build lacks
    // it, replace this single line with: property string homeDir: "/home/pedro"
    property string homeDir: Platform.StandardPaths.writableLocation(Platform.StandardPaths.HomeLocation).toString().replace(/^file:\/\//, "")

    property QtObject workProfile: QtObject {
        property string label: "W"
        property string dir: root.homeDir + "/.claude"
        property string state: "loading"
        property string errorCode: ""
        property var bars: []
        property real worstPercent: 0
        property string worstSeverity: "normal"
    }
    property QtObject personalProfile: QtObject {
        property string label: "P"
        property string dir: root.homeDir + "/.claude-personal"
        property string state: "loading"
        property string errorCode: ""
        property var bars: []
        property real worstPercent: 0
        property string worstSeverity: "normal"
    }

    function readToken(dir) {
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file://" + dir + "/.credentials.json", false);
            xhr.send();
            if (xhr.status !== 0 && xhr.status !== 200) return null;
            if (!xhr.responseText) return null;
            var creds = JSON.parse(xhr.responseText).claudeAiOauth;
            if (!creds || !creds.accessToken) return null;
            return { token: creds.accessToken, expiresAt: creds.expiresAt };
        } catch (e) {
            return null;
        }
    }

    function fetchProfile(profile) {
        profile.state = "loading";
        var creds = readToken(profile.dir);
        if (!creds) { profile.state = "absent"; return; }
        if (creds.expiresAt && Date.now() >= creds.expiresAt) { profile.state = "expired"; return; }

        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var parsed = Usage.parseUsage(JSON.parse(xhr.responseText));
                    profile.bars = parsed.bars;
                    profile.worstPercent = parsed.worstPercent;
                    profile.worstSeverity = parsed.worstSeverity;
                    profile.state = "ok";
                } catch (e) {
                    profile.errorCode = "parse";
                    profile.state = "error";
                }
            } else if (xhr.status === 401) {
                profile.state = "expired";
            } else {
                profile.errorCode = String(xhr.status);
                profile.state = "error";
            }
        };
        xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
        xhr.setRequestHeader("Authorization", "Bearer " + creds.token);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send();
    }

    function fetchAll() {
        fetchProfile(workProfile);
        fetchProfile(personalProfile);
    }

    function severityColor(sev) {
        if (sev === "critical") return Kirigami.Theme.negativeTextColor;
        if (sev === "warning") return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.positiveTextColor;
    }

    function compactText(p) {
        if (p.state === "ok") return p.label + " " + Math.round(p.worstPercent) + "%";
        if (p.state === "absent") return p.label + " —";
        if (p.state === "loading") return p.label + " …";
        return p.label + " !";
    }

    function compactColor(p) {
        if (p.state === "ok") return severityColor(p.worstSeverity);
        if (p.state === "error" || p.state === "expired") return Kirigami.Theme.negativeTextColor;
        return Kirigami.Theme.textColor;
    }

    Component.onCompleted: fetchAll()

    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.fetchAll()
    }
    onExpandedChanged: if (expanded) fetchAll()

    compactRepresentation: MouseArea {
        implicitWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "help-about"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PlasmaComponents3.Label {
                text: root.compactText(root.workProfile)
                color: root.compactColor(root.workProfile)
            }
            PlasmaComponents3.Label { text: "·"; opacity: 0.6 }
            PlasmaComponents3.Label {
                text: root.compactText(root.personalProfile)
                color: root.compactColor(root.personalProfile)
            }
        }
    }

    fullRepresentation: PlasmaComponents3.Label {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "Work: " + root.workProfile.state + " " + Math.round(root.workProfile.worstPercent)
              + "%\nPersonal: " + root.personalProfile.state
    }
}
```

- [ ] **Step 2: Install and verify live data**

Run: `fish plasmoid/install.fish; and plasmoidviewer -a com.pedroou.claudeusage`
Expected: compact shows `W 43%` (or current) colored green, and `P —` (personal profile absent on this machine). The placeholder popup shows `Work: ok 43%` / `Personal: absent`.

Check the console output of `plasmoidviewer` for QML errors; there must be none. Confirm the `homeDir` resolution produced a real path (the Work bar shows a number, not `!` or `—`). If the Work bar shows `!`/`—` and the console logs a `Qt.labs.platform` import error, apply the hardcoded-`homeDir` fallback noted in the code comment and re-run.

- [ ] **Step 3: Commit**

```bash
git add plasmoid/package/contents/ui/main.qml
git commit -m "feat(plasmoid): fetch usage per profile and bind compact view"
```

---

## Task 6: Tabbed popup with usage bars

**Files:**
- Create: `plasmoid/package/contents/ui/UsageBar.qml`
- Create: `plasmoid/package/contents/ui/ProfileTab.qml`
- Modify: `plasmoid/package/contents/ui/main.qml` (replace `fullRepresentation`)

**Interfaces:**
- Consumes: each profile `QtObject` from Task 5 and `severityColor(sev)` from `root`.
- `UsageBar.qml` API: properties `label` (string), `percent` (real), `severity` (string), `resetsAt` (string). Uses `Usage.resetText` for the reset line.
- `ProfileTab.qml` API: property `profile` (the `QtObject`); renders a `Repeater` of `UsageBar` when `profile.state==="ok"`, else a centered status message.

- [ ] **Step 1: Create `UsageBar.qml`**

Create `plasmoid/package/contents/ui/UsageBar.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/usage.js" as Usage

ColumnLayout {
    id: bar
    property string label: ""
    property real percent: 0
    property string severity: "normal"
    property string resetsAt: ""

    function severityColor(sev) {
        if (sev === "critical") return Kirigami.Theme.negativeTextColor;
        if (sev === "warning") return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.positiveTextColor;
    }

    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents3.Label { text: bar.label; Layout.fillWidth: true }
        PlasmaComponents3.Label {
            text: Math.round(bar.percent) + "%"
            color: bar.severityColor(bar.severity)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: Kirigami.Units.gridUnit * 0.6
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, bar.percent / 100))
            height: parent.height
            radius: parent.radius
            color: bar.severityColor(bar.severity)
        }
    }

    PlasmaComponents3.Label {
        text: Usage.resetText(bar.resetsAt, Date.now())
        opacity: 0.7
        font: Kirigami.Theme.smallFont
    }
}
```

- [ ] **Step 2: Create `ProfileTab.qml`**

Create `plasmoid/package/contents/ui/ProfileTab.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

ColumnLayout {
    id: tab
    property QtObject profile: null
    spacing: Kirigami.Units.largeSpacing

    function statusMessage(p) {
        if (!p) return "";
        if (p.state === "absent") return "Not logged in — run claude-personal.";
        if (p.state === "expired") return "Token expired — open Claude for this profile to refresh.";
        if (p.state === "error") return "Couldn't reach the usage API (" + p.errorCode + ").";
        if (p.state === "loading") return "Loading…";
        return "";
    }

    Repeater {
        model: (tab.profile && tab.profile.state === "ok") ? tab.profile.bars : []
        delegate: UsageBar {
            Layout.fillWidth: true
            label: modelData.label
            percent: modelData.percent
            severity: modelData.severity
            resetsAt: modelData.resetsAt || ""
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: !tab.profile || tab.profile.state !== "ok"
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: tab.statusMessage(tab.profile)
    }
}
```

- [ ] **Step 3: Replace `fullRepresentation` in `main.qml`**

In `plasmoid/package/contents/ui/main.qml`, replace the entire `fullRepresentation: PlasmaComponents3.Label { … }` block with:

```qml
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 16
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            Kirigami.Heading { level: 3; text: "Claude Usage"; Layout.fillWidth: true }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                onClicked: root.fetchAll()
            }
        }

        PlasmaComponents3.TabBar {
            id: tabBar
            Layout.fillWidth: true
            PlasmaComponents3.TabButton { text: "Work" }
            PlasmaComponents3.TabButton { text: "Personal" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            ProfileTab { profile: root.workProfile }
            ProfileTab { profile: root.personalProfile }
        }
    }
```

Add `import QtQuick.Layouts` is already present; ensure `StackLayout` is available (it is part of `QtQuick.Layouts`).

- [ ] **Step 4: Install and verify the popup**

Run: `fish plasmoid/install.fish; and plasmoidviewer -a com.pedroou.claudeusage`
Expected:
- Compact still shows `W 43% · P —`.
- Clicking opens a popup titled "Claude Usage" with a refresh button and two tabs.
- **Work** tab shows two bars ("Session (5h)", "Weekly") with fills, percentages, and "resets in …" lines.
- **Personal** tab shows "Not logged in — run claude-personal."
- The refresh button re-fetches without error.

No QML errors in the `plasmoidviewer` console.

- [ ] **Step 5: Commit**

```bash
git add plasmoid/package/contents/ui/UsageBar.qml plasmoid/package/contents/ui/ProfileTab.qml plasmoid/package/contents/ui/main.qml
git commit -m "feat(plasmoid): tabbed popup with per-profile usage bars"
```

---

## Task 7: Repo install hook + docs

**Files:**
- Modify: `install.fish` (repo root)
- Modify: `README.md`

**Interfaces:**
- Consumes: `plasmoid/install.fish` from Task 4.

- [ ] **Step 1: Offer plasmoid install from the root installer**

At the end of the repo-root `install.fish`, before the final `echo`, add:

```fish
if command -q kpackagetool6
    read -l -P "Also install the Claude Usage panel widget (plasmoid)? [y/N] " reply
    if string match -qi y -- "$reply"
        fish $repo_dir/plasmoid/install.fish
    end
end
```

(`$repo_dir` is already defined at the top of `install.fish`.)

- [ ] **Step 2: Verify the prompt path**

Run: `fish -n install.fish`
Expected: no output (syntax OK).

Run (dry check that it locates the plasmoid installer): `test -f plasmoid/install.fish; and echo FOUND`
Expected: `FOUND`.

- [ ] **Step 3: Document it in the README**

Add a new section to `README.md` after the "Automatic config sync" section:

```markdown
## Usage panel widget (KDE Plasma 6)

A plasmoid that shows both profiles' usage-limit percentages in your panel and
expands, on click, to a tab-per-profile popup of usage bars (5-hour, weekly, and
any model-scoped weekly limit) — the same numbers as Claude Code's `/usage`.

Install it:

    fish plasmoid/install.fish
    # then: right-click panel → Add Widgets → search "Claude Usage"

It reads each profile's OAuth token from that profile's `.credentials.json` and
calls the same usage endpoint the TUI uses. If a profile isn't logged in, its
tab says so; if its token has expired, launch `claude` for that profile once to
refresh (the widget does not refresh tokens itself).

**Caveat:** the usage endpoint is undocumented Claude Code internals. A future
`claude` release could change it and break the widget until updated; all the
response-shape logic is isolated in `plasmoid/package/contents/code/usage.js`
with Node tests in `plasmoid/test/`.
```

- [ ] **Step 4: Run the full test suite once more**

Run: `node --test plasmoid/test/usage.test.js`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add install.fish README.md
git commit -m "docs(plasmoid): install hook and README section"
```

---

## Self-review notes

- **Spec coverage:** data source & headers (Tasks 4–5, Global Constraints), token per profile (Task 5 `readToken`), which bars incl. scoped-when-active (Task 3), compact icon+two-% (Tasks 4–5), tabbed popup with reset lines (Task 6), error/absent/expired states (Tasks 5–6), 5-min poll + fetch-on-open + manual refresh (Tasks 5–6), pure-logic isolation + Node tests + fixtures (Tasks 1–3), install under `plasmoid/` + root hook + README (Tasks 4, 7). All covered.
- **Known implementation risk carried into execution:** `$HOME` resolution in QML uses `Qt.labs.platform` `StandardPaths.HomeLocation` (module verified present on this machine). Task 5 Step 2's verification explicitly checks the resolved path worked and points to the one-line hardcoded fallback (documented in the code comment) if the import ever fails.
- **Type consistency:** the profile `QtObject` property set (`state`, `errorCode`, `bars`, `worstPercent`, `worstSeverity`) is defined in Task 5 and consumed unchanged in Task 6; `severityColor` is defined identically in `main.qml` and `UsageBar.qml` (the bar component is standalone, so the small duplication is intentional).
```
