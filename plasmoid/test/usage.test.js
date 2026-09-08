// Tests for the plan-usage footer's pure layer.
//   node --test plasmoid/test/usage.test.js

const test = require("node:test")
const assert = require("node:assert")
const Usage = require("../package/contents/code/usage.js")

const NOW = Date.parse("2026-09-08T12:00:00Z")

function profile(over) {
    return Object.assign({
        id: "work",
        state: "ok",
        bars: [
            {id: "session", label: "Session", percent: 11, severity: "normal",
             resetsAt: "2026-09-08T16:30:00Z", active: true},
            {id: "weekly", label: "Weekly", percent: 5, severity: "normal",
             resetsAt: "2026-09-10T16:00:00Z", active: false},
            {id: "scoped:Fable", label: "Fable", percent: 0, severity: "normal",
             resetsAt: null, active: false}
        ]
    }, over || {})
}

test("the bar you picked is the bar you get", () => {
    assert.equal(Usage.barFor(profile(), "weekly").label, "Weekly")
    assert.equal(Usage.barFor(profile(), "scoped:Fable").label, "Fable")
})

test("a bar the plan no longer has falls back to the one actually counting", () => {
    assert.equal(Usage.barFor(profile(), "scoped:Gone").label, "Session")
})

test("with nothing active it falls back to the first bar rather than nothing", () => {
    const p = profile()
    p.bars.forEach(b => { b.active = false })
    assert.equal(Usage.barFor(p, "nope").label, "Session")
})

test("a profile with no bars has no bar", () => {
    assert.equal(Usage.barFor(profile({bars: []}), "session"), null)
    assert.equal(Usage.barFor(null, "session"), null)
})

test("severity comes from the API when it gives one", () => {
    assert.equal(Usage.severity({percent: 99, severity: "normal"}), "normal")
    assert.equal(Usage.severity({percent: 5, severity: "warning"}), "warning")
    assert.equal(Usage.severity({percent: 5, severity: "exceeded"}), "critical")
})

test("and from the percentage when it does not", () => {
    assert.equal(Usage.severity({percent: 10}), "normal")
    assert.equal(Usage.severity({percent: 70}), "warning")
    assert.equal(Usage.severity({percent: 95}), "critical")
    assert.equal(Usage.severity(null), "normal")
})

test("the reset time reads as a countdown", () => {
    assert.equal(Usage.resetText("2026-09-08T16:30:00Z", NOW), "resets in 4h 30m")
    assert.equal(Usage.resetText("2026-09-08T12:45:00Z", NOW), "resets in 45m")
    assert.equal(Usage.resetText("2026-09-10T12:00:00Z", NOW), "resets in 2d")
    assert.equal(Usage.resetText("2026-09-10T18:00:00Z", NOW), "resets in 2d 6h")
})

test("a limit with no reset time says nothing rather than lying", () => {
    assert.equal(Usage.resetText(null, NOW), "")
    assert.equal(Usage.resetText("not a date", NOW), "")
})

test("a reset already due does not count backwards", () => {
    assert.equal(Usage.resetText("2026-09-08T11:00:00Z", NOW), "resets any moment")
})

test("every profile state names its own fix", () => {
    assert.equal(Usage.stateMessage(profile()), "")
    assert.equal(Usage.stateMessage(profile({state: "absent"})), "Not signed in")
    assert.match(Usage.stateMessage(profile({state: "expired"})), /run claude/)
    assert.match(Usage.stateMessage(profile({state: "error"})), /Couldn't reach/)
    assert.match(Usage.stateMessage(profile({bars: []})), /no limits/)
})

test("profiles are found by id and listed in a stable order", () => {
    const usage = {profiles: [profile(), profile({id: "personal", state: "absent", bars: []})]}
    assert.equal(Usage.profileById(usage, "personal").state, "absent")
    assert.equal(Usage.profileById(usage, "nope"), null)
    assert.deepEqual(Usage.selectableProfiles(usage).map(p => p.id), ["work", "personal"])
    assert.deepEqual(Usage.selectableProfiles(null), [])
})
