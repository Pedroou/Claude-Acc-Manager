// Pure display helpers for the session list. No Qt or QML dependency, so the
// same file is exercised by plasmoid/test/sessions.test.js under node.
//
// Deliberately not `.pragma library`: that directive is not valid JavaScript, and
// it would stop node from loading this file at all. Nothing here reads the QML
// context, so the only thing the pragma would buy is sharing one copy.

// Every state the widget knows, most wanting-your-attention first. The order is
// the one the collector sorts by and the one the summary reads in.
var STATES = ["waiting", "error", "running", "working", "shell", "done", "unknown"]

// How each state reads in the summary sentence, as a plural-safe noun phrase.
var STATE_NOUNS = {
    waiting: "waiting for you",
    error: "with an error",
    running: "running",
    working: "working",
    shell: "in a shell",
    done: "done",
    unknown: "in an unknown state"
}

// The colour each state falls back to when the user has not picked one. Chosen
// to sit clear of a dark panel without going illegible on a light one: these are
// mid-tones, the weight most palettes reserve for exactly that job.
//
// Blue is deliberately absent. It is the commonest convention for "in progress",
// but it disappears into a dark blue panel, which is the whole reason these
// stopped being theme colours.
var DEFAULT_COLORS = {
    waiting: "#f97316", // orange — a person has to do something
    error: "#ef4444", // red — the long-standing meaning, worth not reinventing
    running: "#eab308", // yellow — busy, but nobody is being waited on
    working: "#06b6d4", // cyan — active, and the one that had to leave blue
    shell: "#94a3b8", // slate — a real state, but not one to shout about
    done: "#22c55e", // green — finished
    unknown: "#94a3b8"
}

function defaultColor(state) {
    return DEFAULT_COLORS[state] || DEFAULT_COLORS.unknown
}

// Bars are all one height. Colour alone carries the state — a deliberate choice
// to keep the panel from looking like a jagged little chart.
function railFraction() {
    return 1.0
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

// The summary, broken into its pieces so each count can be drawn in its own
// colour. `[{state, count, noun}]`, in attention order.
function summaryParts(counts) {
    var parts = []
    if (!counts) {
        return parts
    }
    for (var i = 0; i < STATES.length; i++) {
        var state = STATES[i]
        if (counts[state]) {
            parts.push({state: state, count: counts[state], noun: STATE_NOUNS[state]})
        }
    }
    return parts
}

// The one sentence that answers "does anything need me?".
function headline(counts) {
    if (!counts || !counts.total) {
        return "Nothing running"
    }
    return summaryParts(counts).map(function (p) {
        return p.count + " " + p.noun
    }).join(", ")
}

// Same information, one state per line, for the panel's hover tooltip.
function tooltipLines(counts) {
    if (!counts || !counts.total) {
        return "No sessions running"
    }
    return summaryParts(counts).map(function (p) {
        return p.count + " " + p.noun
    }).join("\n")
}

// The state that decides the widget's overall tone.
//
// Anything blocked on a person wins outright, however few — that is the question
// the panel exists to answer. Failing that it is simply the biggest group, with
// ties broken by which state is more urgent.
function dominantState(counts) {
    if (!counts || !counts.total) {
        return "none"
    }
    if (counts.waiting) {
        return "waiting"
    }
    var best = "none"
    var bestCount = 0
    for (var i = 0; i < STATES.length; i++) {
        var state = STATES[i]
        if (counts[state] > bestCount) {
            best = state
            bestCount = counts[state]
        }
    }
    return best
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
    var counts = {total: 0}
    for (var i = 0; i < STATES.length; i++) {
        counts[STATES[i]] = 0
    }
    for (var j = 0; j < (sessions ? sessions.length : 0); j++) {
        var state = sessions[j].state
        if (counts[state] === undefined) {
            state = "unknown"
        }
        counts[state] += 1
        counts.total += 1
    }
    return counts
}

// What a session is called, allowing for a nickname the user has given it and
// for the privacy toggle that blanks names out.
function displayName(session, nicknames, censored) {
    if (censored) {
        return "Session " + session.pid
    }
    var nick = nicknames ? nicknames[session.sessionId] : undefined
    return (nick !== undefined && nick !== "") ? nick : session.name
}

// The second line of a row: where the session is, and what it wants. Blank when
// names are censored, which is the point of censoring them.
function context(session, showProfile, censored) {
    if (censored) {
        return ""
    }
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

function label(key, settings, shortKey) {
    return (settings && settings.shortLabels && shortKey) ? shortKey : key
}

// The rows behind an expanded session, in the order they are read: who, how
// long, where, then the identifiers you would otherwise dig out of `ps`.
//
// A row with no value never appears — a session outside a git repository simply
// has no Repository line rather than an empty one.
function detailRows(session, settings, nowMs, censored) {
    var s = settings || {}
    var rows = []

    function add(id, key, value, copyable) {
        if (value === undefined || value === null || value === "" || value === "0") {
            return
        }
        rows.push({id: id, key: key, value: String(value), copyable: copyable === true})
    }

    var branchShown = s.detailBranch !== false && session.branch
    var branchOnItsOwn = branchShown && s.branchSeparate === true

    var repository = session.repository
    if (repository && branchShown && !branchOnItsOwn) {
        repository = repository + "/" + session.branch
    }

    add("profile", "Profile", session.profile, false)
    add("uptime", "Uptime", age(session.startedAt, nowMs), false)
    if (!censored) {
        add("directory", label("Directory", s, "Dir"), session.cwd, true)
    }
    if (s.detailRepository !== false && !censored) {
        add("repository", label("Repository", s, "Repo"), repository, true)
    }
    if (branchOnItsOwn && !censored) {
        add("branch", "Branch", session.branch, true)
    }
    if (s.detailSession !== false) {
        add("session", "Session", session.sessionId, true)
    }
    if (s.detailProcess !== false) {
        add("process", "Process", session.pid, true)
    }
    if (s.detailVersion !== false) {
        add("version", "Version", session.version, true)
    }
    return rows
}

// The command that reopens a session in a new terminal. `claude --resume <id>`
// from its own directory is the one that actually lands you back in it.
function resumeCommand(session) {
    var launcher = session.profile === "personal" ? "claude-personal" : "claude"
    return "cd " + shellQuote(session.cwd) + " && " + launcher + " --resume " + session.sessionId
}

function shellQuote(text) {
    if (text === undefined || text === null) {
        return "''"
    }
    if (/^[A-Za-z0-9_@%+=:,.\/-]+$/.test(text)) {
        return text
    }
    return "'" + String(text).replace(/'/g, "'\\''") + "'"
}

// Everything on screen for one session, as plain text worth pasting somewhere.
function detailsAsText(session, settings, nowMs, nicknames, censored) {
    var lines = [displayName(session, nicknames, censored) + " — " + session.label]
    var second = context(session, true, censored)
    if (second) {
        lines.push(second)
    }
    var rows = detailRows(session, settings, nowMs, censored)
    for (var i = 0; i < rows.length; i++) {
        lines.push(rows[i].key + ": " + rows[i].value)
    }
    return lines.join("\n")
}

// Present only under node; QML ignores it.
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        STATES: STATES,
        DEFAULT_COLORS: DEFAULT_COLORS,
        defaultColor: defaultColor,
        railFraction: railFraction,
        age: age,
        summaryParts: summaryParts,
        headline: headline,
        tooltipLines: tooltipLines,
        dominantState: dominantState,
        visible: visible,
        countsFor: countsFor,
        displayName: displayName,
        context: context,
        detailRows: detailRows,
        resumeCommand: resumeCommand,
        shellQuote: shellQuote,
        detailsAsText: detailsAsText
    }
}
