// Tests for the widget's pure display layer.
//   node --test plasmoid/test/sessions.test.js
//
// The QML side is deliberately thin — it binds these results to components — so
// everything with a decision in it is checked here without a running Plasma shell.

const test = require("node:test")
const assert = require("node:assert")
const Sessions = require("../package/contents/code/sessions.js")

const NOW = 1788543348520

function session(over) {
    return Object.assign({
        pid: 1234,
        profile: "work",
        name: "lab2-76",
        cwd: "/home/u/Projects/lab2",
        dir: "lab2",
        repository: "lab2",
        branch: "main",
        sessionId: "abc-123",
        kind: "interactive",
        status: "busy",
        state: "working",
        label: "Working",
        detail: "",
        startedAt: NOW - 3600_000,
        statusUpdatedAt: NOW - 60_000,
        version: "2.1.263"
    }, over || {})
}

test("age reports the coarsest unit that still says something", () => {
    assert.equal(Sessions.age(NOW, NOW), "0s")
    assert.equal(Sessions.age(NOW - 42_000, NOW), "42s")
    assert.equal(Sessions.age(NOW - 60_000, NOW), "1m")
    assert.equal(Sessions.age(NOW - 59 * 60_000, NOW), "59m")
    assert.equal(Sessions.age(NOW - 60 * 60_000, NOW), "1h")
    assert.equal(Sessions.age(NOW - 80 * 60_000, NOW), "1h 20m")
    assert.equal(Sessions.age(NOW - 26 * 3600_000, NOW), "1d 2h")
    assert.equal(Sessions.age(NOW - 48 * 3600_000, NOW), "2d")
})

test("age is blank when the timestamp is missing, never 'NaN' or a 1970 date", () => {
    assert.equal(Sessions.age(0, NOW), "")
    assert.equal(Sessions.age(undefined, NOW), "")
})

test("a clock that has drifted backwards does not produce a negative age", () => {
    assert.equal(Sessions.age(NOW + 5000, NOW), "0s")
})

test("every state has a colour, and none of them is blue", () => {
    for (const state of Sessions.STATES) {
        const hex = Sessions.defaultColor(state)
        assert.match(hex, /^#[0-9a-f]{6}$/, state + " needs a colour")
        // Blue is the commonest "in progress" convention and the reason these
        // stopped being theme colours: it vanishes into a dark blue panel.
        const r = parseInt(hex.slice(1, 3), 16)
        const g = parseInt(hex.slice(3, 5), 16)
        const b = parseInt(hex.slice(5, 7), 16)
        assert.ok(!(b > r + 40 && b > g + 40), state + " is a blue: " + hex)
    }
    assert.equal(Sessions.defaultColor("something-new"), Sessions.defaultColor("unknown"))
})

test("bars are all one height, so the panel is not a jagged chart", () => {
    assert.equal(Sessions.railFraction(), 1.0)
})

test("the summary breaks into parts so each count can wear its own colour", () => {
    const parts = Sessions.summaryParts({waiting: 1, working: 3, done: 2, total: 6})
    assert.deepEqual(parts.map(p => p.state), ["waiting", "working", "done"])
    assert.deepEqual(parts.map(p => p.count), [1, 3, 2])
    assert.equal(parts[0].noun, "waiting for you")
})

test("the headline leads with whatever is blocked, then what failed", () => {
    assert.equal(Sessions.headline({waiting: 1, error: 1, running: 2, working: 3, done: 2, total: 9}),
                 "1 waiting for you, 1 with an error, 2 running, 3 working, 2 done")
    assert.equal(Sessions.headline({working: 2, total: 2}), "2 working")
    assert.equal(Sessions.headline({shell: 1, total: 1}), "1 in a shell")
})

test("the headline says something useful when nothing is running", () => {
    assert.equal(Sessions.headline({total: 0}), "Nothing running")
    assert.equal(Sessions.headline(null), "Nothing running")
})

test("the tooltip is the same facts, one per line", () => {
    assert.equal(Sessions.tooltipLines({waiting: 1, done: 2, total: 3}),
                 "1 waiting for you\n2 done")
    assert.equal(Sessions.tooltipLines({total: 0}), "No sessions running")
})

test("the dominant state is the biggest group", () => {
    assert.equal(Sessions.dominantState({working: 5, done: 1, total: 6}), "working")
    assert.equal(Sessions.dominantState({working: 1, done: 4, total: 5}), "done")
    assert.equal(Sessions.dominantState({running: 3, working: 2, total: 5}), "running")
    assert.equal(Sessions.dominantState({total: 0}), "none")
})

test("but anything blocked on a person wins, however few", () => {
    assert.equal(Sessions.dominantState({waiting: 1, working: 9, total: 10}), "waiting")
})

test("a tie goes to the more urgent state", () => {
    assert.equal(Sessions.dominantState({error: 2, done: 2, total: 4}), "error")
    assert.equal(Sessions.dominantState({running: 2, working: 2, total: 4}), "running")
})

test("finished sessions can be hidden without disturbing the rest", () => {
    const sessions = [
        {name: "a", state: "waiting"},
        {name: "b", state: "working"},
        {name: "c", state: "done"}
    ]
    assert.deepEqual(Sessions.visible(sessions, {showDone: true}).map(s => s.name), ["a", "b", "c"])
    assert.deepEqual(Sessions.visible(sessions, {showDone: false}).map(s => s.name), ["a", "b"])
    assert.deepEqual(Sessions.visible(sessions, {}).map(s => s.name), ["a", "b", "c"])
    assert.deepEqual(Sessions.visible(undefined, {}), [])
})

test("the counts follow the filter, so the header can never contradict the list", () => {
    const sessions = [
        {state: "waiting"}, {state: "working"}, {state: "working"}, {state: "done"}
    ]
    const kept = Sessions.visible(sessions, {showDone: false})
    const counts = Sessions.countsFor(kept)
    assert.equal(counts.total, 3)
    assert.equal(counts.working, 2)
    assert.equal(counts.done, 0)
})

test("a status this version has never heard of is counted, not dropped", () => {
    const counts = Sessions.countsFor([{state: "hibernating"}])
    assert.equal(counts.unknown, 1)
    assert.equal(counts.total, 1)
})

test("a nickname replaces the name, and censoring replaces both", () => {
    const s = session()
    assert.equal(Sessions.displayName(s, {}, false), "lab2-76")
    assert.equal(Sessions.displayName(s, {"abc-123": "the refactor"}, false), "the refactor")
    assert.equal(Sessions.displayName(s, {"abc-123": ""}, false), "lab2-76")
    assert.equal(Sessions.displayName(s, {"abc-123": "the refactor"}, true), "Session 1234")
})

test("the row's second line says where the session is and what it wants", () => {
    assert.equal(
        Sessions.context(session({detail: "input needed"}), false, false),
        "lab2 — input needed")
    assert.equal(
        Sessions.context(session({profile: "personal", detail: ""}), true, false),
        "personal — lab2")
    assert.equal(Sessions.context(session({detail: ""}), false, false), "lab2")
})

test("censoring leaves no second line at all", () => {
    assert.equal(Sessions.context(session({detail: "input needed"}), true, true), "")
})

test("the detail rows read in a fixed order", () => {
    const keys = Sessions.detailRows(session(), {}, NOW, false).map(r => r.key)
    assert.deepEqual(keys,
        ["Profile", "Uptime", "Directory", "Repository", "Session", "Process", "Version"])
})

test("the branch rides on the repository by default, and can move to its own row", () => {
    const merged = Sessions.detailRows(session(), {}, NOW, false)
    assert.equal(merged.find(r => r.key === "Repository").value, "lab2/main")
    assert.equal(merged.find(r => r.key === "Branch"), undefined)

    const split = Sessions.detailRows(session(), {branchSeparate: true}, NOW, false)
    assert.equal(split.find(r => r.key === "Repository").value, "lab2")
    assert.equal(split.find(r => r.key === "Branch").value, "main")
    assert.deepEqual(split.map(r => r.key),
        ["Profile", "Uptime", "Directory", "Repository", "Branch", "Session", "Process", "Version"])
})

test("turning the branch off removes it from both places", () => {
    const merged = Sessions.detailRows(session(), {detailBranch: false}, NOW, false)
    assert.equal(merged.find(r => r.key === "Repository").value, "lab2")

    const split = Sessions.detailRows(session(), {detailBranch: false, branchSeparate: true}, NOW, false)
    assert.equal(split.find(r => r.key === "Branch"), undefined)
    assert.equal(split.find(r => r.key === "Repository").value, "lab2")
})

test("each optional row can be turned off on its own", () => {
    const off = {detailRepository: false, detailSession: false, detailProcess: false, detailVersion: false}
    assert.deepEqual(Sessions.detailRows(session(), off, NOW, false).map(r => r.key),
                     ["Profile", "Uptime", "Directory"])
})

test("a session outside a repository simply has no repository row", () => {
    const keys = Sessions.detailRows(session({repository: "", branch: ""}), {}, NOW, false).map(r => r.key)
    assert.deepEqual(keys, ["Profile", "Uptime", "Directory", "Session", "Process", "Version"])
})

test("the labels can be abbreviated", () => {
    const keys = Sessions.detailRows(session(), {shortLabels: true}, NOW, false).map(r => r.key)
    assert.ok(keys.includes("Dir"))
    assert.ok(keys.includes("Repo"))
    assert.ok(!keys.includes("Directory"))
})

test("censoring hides the rows that would give the path away", () => {
    const keys = Sessions.detailRows(session(), {}, NOW, true).map(r => r.key)
    assert.deepEqual(keys, ["Profile", "Uptime", "Session", "Process", "Version"])
})

test("only the rows worth pasting are click-to-copy", () => {
    const rows = Sessions.detailRows(session(), {branchSeparate: true}, NOW, false)
    const copyable = rows.filter(r => r.copyable).map(r => r.key)
    assert.deepEqual(copyable,
        ["Directory", "Repository", "Branch", "Session", "Process", "Version"])
})

test("the resume command lands you back in the session, in its own directory", () => {
    assert.equal(Sessions.resumeCommand(session()),
                 "cd /home/u/Projects/lab2 && claude --resume abc-123")
    assert.equal(Sessions.resumeCommand(session({profile: "personal"})),
                 "cd /home/u/Projects/lab2 && claude-personal --resume abc-123")
})

test("a path with a space or a quote in it is still a safe command", () => {
    assert.equal(Sessions.shellQuote("/home/u/my projects"), "'/home/u/my projects'")
    assert.equal(Sessions.shellQuote("/home/u/it's"), "'/home/u/it'\\''s'")
    assert.equal(Sessions.shellQuote("/plain/path-1.2"), "/plain/path-1.2")
})

test("copying an expanded session gives you everything on screen", () => {
    const text = Sessions.detailsAsText(session({detail: "input needed"}), {}, NOW, {}, false)
    const lines = text.split("\n")
    assert.equal(lines[0], "lab2-76 — Working")
    assert.equal(lines[1], "work — lab2 — input needed")
    assert.ok(lines.includes("Repository: lab2/main"))
    assert.ok(lines.includes("Session: abc-123"))
})
