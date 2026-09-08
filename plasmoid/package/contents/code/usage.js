// Pure helpers for the plan-usage footer. No Qt or QML dependency, so the same
// file is exercised by plasmoid/test/usage.test.js under node.

// Which bar a profile should show. The user's pick wins; failing that the limit
// the API says is currently active, which is the one actually biting; failing
// that whatever came first.
function barFor(profile, wantedId) {
    var bars = (profile && profile.bars) || []
    if (!bars.length) {
        return null
    }
    for (var i = 0; i < bars.length; i++) {
        if (bars[i].id === wantedId) {
            return bars[i]
        }
    }
    for (var j = 0; j < bars.length; j++) {
        if (bars[j].active) {
            return bars[j]
        }
    }
    return bars[0]
}

// green / amber / red, from the API's own severity where it gives one.
function severity(bar) {
    if (!bar) {
        return "normal"
    }
    if (bar.severity === "normal" || bar.severity === "warning") {
        return bar.severity
    }
    if (bar.severity && bar.severity !== "") {
        return "critical"
    }
    var percent = bar.percent || 0
    return percent > 90 ? "critical" : (percent >= 70 ? "warning" : "normal")
}

// "resets in 2h 14m", "resets in 3d". Blank when the API gave no reset time,
// which happens for limits that are not currently counting.
function resetText(resetsAt, nowMs) {
    if (!resetsAt) {
        return ""
    }
    var at = Date.parse(resetsAt)
    if (isNaN(at)) {
        return ""
    }
    var seconds = Math.round((at - nowMs) / 1000)
    if (seconds <= 0) {
        return "resets any moment"
    }
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) {
        return "resets in " + Math.max(1, minutes) + "m"
    }
    var hours = Math.floor(minutes / 60)
    if (hours < 24) {
        return minutes % 60 ? "resets in " + hours + "h " + (minutes % 60) + "m"
                            : "resets in " + hours + "h"
    }
    var days = Math.floor(hours / 24)
    return hours % 24 ? "resets in " + days + "d " + (hours % 24) + "h"
                      : "resets in " + days + "d"
}

// What to say when a profile has no bars to draw. Each one names the fix.
function stateMessage(profile) {
    if (!profile) {
        return "No such profile"
    }
    switch (profile.state) {
    case "ok":
        return (profile.bars && profile.bars.length) ? "" : "This plan reports no limits"
    case "absent":
        return "Not signed in"
    case "expired":
        return "Signed out — run claude to sign back in"
    default:
        return "Couldn't reach the usage API"
    }
}

function profileById(usage, id) {
    var list = (usage && usage.profiles) || []
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === id) {
            return list[i]
        }
    }
    return null
}

// The profiles worth putting in the selector: any that exist, in a stable order,
// so the list does not reshuffle as tokens expire.
function selectableProfiles(usage) {
    var list = (usage && usage.profiles) || []
    return list.filter(function (p) {
        return p && p.id
    })
}

// Present only under node; QML ignores it.
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        barFor: barFor,
        severity: severity,
        resetText: resetText,
        stateMessage: stateMessage,
        profileById: profileById,
        selectableProfiles: selectableProfiles
    }
}
