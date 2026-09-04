// Tests for the widget's pure display layer.
//   node --test plasmoid/test/sessions.test.js
//
// The QML side is deliberately thin — it binds these results to components — so
// everything with a decision in it is checked here without a running Plasma shell.

const test = require("node:test")
const assert = require("node:assert")
const Sessions = require("../package/contents/code/sessions.js")

const NOW = 1788543348520

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

test("the headline leads with whatever is blocked", () => {
    assert.equal(Sessions.headline({waiting: 1, working: 3, done: 2, total: 6}),
                 "1 waiting for you, 3 working, 2 done")
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

test("the dominant state is the most urgent one present", () => {
    assert.equal(Sessions.dominantState({waiting: 1, working: 5, total: 6}), "waiting")
    assert.equal(Sessions.dominantState({working: 5, done: 1, total: 6}), "working")
    assert.equal(Sessions.dominantState({done: 1, total: 1}), "done")
    assert.equal(Sessions.dominantState({total: 0}), "none")
})

test("rail length ranks urgency, so colour is never the only signal", () => {
    assert.ok(Sessions.railFraction("waiting") > Sessions.railFraction("working"))
    assert.ok(Sessions.railFraction("working") > Sessions.railFraction("shell"))
    assert.ok(Sessions.railFraction("shell") > Sessions.railFraction("done"))
    assert.equal(Sessions.railFraction("something-new"), Sessions.railFraction("unknown"))
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
    assert.deepEqual(Sessions.countsFor(kept),
                     {waiting: 1, working: 2, shell: 0, done: 0, unknown: 0, total: 3})
})

test("a status this version has never heard of is counted, not dropped", () => {
    assert.deepEqual(Sessions.countsFor([{state: "hibernating"}]),
                     {waiting: 0, working: 0, shell: 0, done: 0, unknown: 1, total: 1})
})

test("the row's second line says where the session is and what it wants", () => {
    assert.equal(
        Sessions.context({dir: "Lab2", detail: "input needed", profile: "work"}, false),
        "Lab2 — input needed")
    assert.equal(
        Sessions.context({dir: "Lab2", detail: "", profile: "personal"}, true),
        "personal — Lab2")
    assert.equal(Sessions.context({dir: "Lab2", profile: "work"}, false), "Lab2")
})
