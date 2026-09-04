// Pure display helpers for the session list. No Qt or QML dependency, so the
// same file is exercised by plasmoid/test/sessions.test.js under node.
//
// Deliberately not `.pragma library`: that directive is not valid JavaScript, and
// it would stop node from loading this file at all. Nothing here reads the QML
// context, so the only thing the pragma would buy is sharing one copy.

// How tall a session's rail is drawn, as a fraction of the space available.
// Height carries the same information as colour, so the panel still reads as a
// hierarchy in a monochrome theme or to a colourblind eye.
var RAIL_FRACTION = {
    waiting: 1.0,
    working: 0.72,
    shell: 0.56,
    done: 0.4,
    unknown: 0.4
}

var STATE_NOUNS = {
    waiting: "waiting for you",
    working: "working",
    shell: "in a shell",
    done: "done",
    unknown: "in an unknown state"
}

function railFraction(state) {
    var f = RAIL_FRACTION[state]
    return f === undefined ? RAIL_FRACTION.unknown : f
}

// "12s", "4m", "1h 20m", "2d 3h" — the coarsest unit that still says something.
function age(sinceMs, nowMs) {
    if (!sinceMs) {
        return ""
    }
    var seconds = Math.max(0, Math.round((nowMs - sinceMs) / 1000))
    if (seconds < 60) {
        return seconds + "s"
    }
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) {
        return minutes + "m"
    }
    var hours = Math.floor(minutes / 60)
    if (hours < 24) {
        return minutes % 60 ? hours + "h " + (minutes % 60) + "m" : hours + "h"
    }
    var days = Math.floor(hours / 24)
    return hours % 24 ? days + "d " + (hours % 24) + "h" : days + "d"
}

// The one sentence that answers "does anything need me?".
function headline(counts) {
    if (!counts || !counts.total) {
        return "Nothing running"
    }
    var parts = []
    var order = ["waiting", "working", "shell", "done", "unknown"]
    for (var i = 0; i < order.length; i++) {
        var state = order[i]
        if (counts[state]) {
            parts.push(counts[state] + " " + STATE_NOUNS[state])
        }
    }
    return parts.join(", ")
}

// Same information, one state per line, for the panel's hover tooltip.
function tooltipLines(counts) {
    if (!counts || !counts.total) {
        return "No sessions running"
    }
    var lines = []
    var order = ["waiting", "working", "shell", "done", "unknown"]
    for (var i = 0; i < order.length; i++) {
        var state = order[i]
        if (counts[state]) {
            lines.push(counts[state] + " " + STATE_NOUNS[state])
        }
    }
    return lines.join("\n")
}

// The state that decides the widget's overall tone: the most urgent one present.
function dominantState(counts) {
    if (!counts || !counts.total) {
        return "none"
    }
    var order = ["waiting", "working", "shell", "done", "unknown"]
    for (var i = 0; i < order.length; i++) {
        if (counts[order[i]]) {
            return order[i]
        }
    }
    return "none"
}

// Sessions the widget should draw, given the user's settings. The collector has
// already sorted them, so this only ever removes.
function visible(sessions, settings) {
    if (!sessions) {
        return []
    }
    if (!settings || settings.showDone !== false) {
        return sessions
    }
    return sessions.filter(function (s) {
        return s.state !== "done"
    })
}

// The counts that go with a filtered list, so the header and the panel never
// disagree with what is on screen.
function countsFor(sessions) {
    var counts = {waiting: 0, working: 0, shell: 0, done: 0, unknown: 0, total: 0}
    for (var i = 0; i < (sessions ? sessions.length : 0); i++) {
        var state = sessions[i].state
        if (counts[state] === undefined) {
            state = "unknown"
        }
        counts[state] += 1
        counts.total += 1
    }
    return counts
}

// The second line of a row: where the session is, and what it is stuck on.
function context(session, showProfile) {
    var bits = []
    if (showProfile && session.profile) {
        bits.push(session.profile)
    }
    if (session.dir) {
        bits.push(session.dir)
    }
    if (session.detail) {
        bits.push(session.detail)
    }
    return bits.join(" — ")
}

// Present only under node; QML ignores it.
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        railFraction: railFraction,
        age: age,
        headline: headline,
        tooltipLines: tooltipLines,
        dominantState: dominantState,
        visible: visible,
        countsFor: countsFor,
        context: context
    }
}
