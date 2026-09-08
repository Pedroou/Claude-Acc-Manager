import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

import "../code/sessions.js" as Sessions

PlasmoidItem {
    id: root

    // Everything the collector last told us, plus a clock the views bind to so
    // "4m ago" keeps counting without each row owning a timer.
    property var sessions: []
    property var profiles: []
    property var usage: null
    property string failure: ""
    property double now: Date.now()
    // Until the first result lands there is nothing to say, and "No sessions
    // running" would be a guess rather than an answer.
    property bool everLoaded: false

    readonly property var shown: Sessions.visible(sessions, plasmoid.configuration)
    readonly property var shownCounts: Sessions.countsFor(shown)
    readonly property bool censored: plasmoid.configuration.censorNames
    // The profile only earns space on a row when there is more than one in play.
    readonly property bool showProfiles: profiles.length > 1
                                         && sessions.some(function (s) { return s.profile === "personal" })

    // Told to every open row when the popup closes, so the next opening starts
    // collapsed rather than showing whatever was left expanded.
    signal collapseAll()

    // Status colours are the widget's own, not the theme's: the theme accent is
    // usually blue, which is exactly what disappears into a blue panel. The
    // defaults live in code/sessions.js so the node tests can check them.
    function tone(state) {
        if (state === "none" || state === "unknown") {
            return Kirigami.Theme.disabledTextColor
        }
        if (!plasmoid.configuration.customColors) {
            return Sessions.defaultColor(state)
        }
        switch (state) {
        case "waiting": return plasmoid.configuration.colorWaiting
        case "error": return plasmoid.configuration.colorError
        case "running": return plasmoid.configuration.colorRunning
        case "working": return plasmoid.configuration.colorWorking
        case "shell": return plasmoid.configuration.colorShell
        case "done": return plasmoid.configuration.colorDone
        default: return Kirigami.Theme.disabledTextColor
        }
    }

    // Widget-local session names. Claude Code owns the real one and rewrites its
    // record constantly, so a rename here is a nickname the widget keeps.
    readonly property var nicknames: {
        try {
            return JSON.parse(plasmoid.configuration.nicknames || "{}")
        } catch (e) {
            return {}
        }
    }

    function setNickname(sessionId, name) {
        var map = {}
        for (var key in nicknames) {
            map[key] = nicknames[key]
        }
        if (name === "" || name === undefined) {
            delete map[sessionId]
        } else {
            map[sessionId] = name
        }
        plasmoid.configuration.nicknames = JSON.stringify(map)
    }

    compactRepresentation: CompactView { widget: root }
    fullRepresentation: FullView { widget: root }

    Plasmoid.status: {
        if (shownCounts.waiting > 0 && plasmoid.configuration.attentionWhenWaiting) {
            return PlasmaCore.Types.NeedsAttentionStatus
        }
        return shownCounts.total > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    }

    toolTipMainText: i18n("Claude Code Sessions")
    toolTipSubText: failure !== "" ? failure : Sessions.tooltipLines(shownCounts)
    toolTipTextFormat: Text.PlainText

    Plasma5Support.DataSource {
        id: collector
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source)
            root.everLoaded = true

            var stdout = (data["stdout"] || "").trim()
            if (data["exit code"] !== 0 || stdout === "") {
                root.failure = (data["stderr"] || "").trim()
                        || i18n("Couldn't read the session registry.")
                return
            }
            try {
                var payload = JSON.parse(stdout)
            } catch (e) {
                root.failure = i18n("The session registry didn't parse.")
                return
            }
            root.failure = ""
            root.sessions = payload.sessions || []
            root.profiles = payload.profiles || []
            root.now = Date.now()
        }
    }

    // Plan usage is a network call and plan limits move slowly, so it runs on its
    // own much lazier schedule rather than riding the session poll.
    Plasma5Support.DataSource {
        id: usageSource
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source)
            var stdout = (data["stdout"] || "").trim()
            if (data["exit code"] !== 0 || stdout === "") {
                return
            }
            try {
                root.usage = JSON.parse(stdout)
            } catch (e) {
                // Leave the last good reading on screen rather than blanking it.
            }
        }
    }

    readonly property string usagePath: {
        var url = Qt.resolvedUrl("../scripts/claude-usage").toString()
        return url.replace(/^file:\/\//, "")
    }

    function refreshUsage() {
        if (!plasmoid.configuration.showUsage) {
            return
        }
        usageSource.connectSource("'" + usagePath.replace(/'/g, "'\\''") + "'")
    }

    Timer {
        interval: 5 * 60 * 1000
        running: plasmoid.configuration.showUsage
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshUsage()
    }

    // Kept apart from the collector so a signal's empty output is never mistaken
    // for a failed read of the registry.
    Plasma5Support.DataSource {
        id: actions
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source)
            root.refresh()
        }
    }

    // SIGTERM is the graceful path: Claude Code registers a handler for it that
    // runs its own shutdown, so the session closes the way it would if you shut
    // the terminal. The transcript is on disk either way, and `claude --resume`
    // picks it back up — which is what right-clicking the row copies.
    function endSession(pid) {
        actions.connectSource("kill -TERM " + parseInt(pid, 10))
    }

    // QML has no clipboard of its own; a TextEdit does, and this is the usual way
    // to borrow it.
    TextEdit {
        id: clipboard
        visible: false
        function put(text) {
            clipboard.text = text
            clipboard.selectAll()
            clipboard.copy()
            clipboard.deselect()
        }
    }

    function copyToClipboard(text) {
        clipboard.put(text)
    }

    // The collector lives beside this file inside the package, so it is found
    // whether the widget was installed for the user or shipped system-wide.
    readonly property string collectorPath: {
        var url = Qt.resolvedUrl("../scripts/claude-sessions").toString()
        return url.replace(/^file:\/\//, "")
    }

    function refresh() {
        collector.connectSource("'" + collectorPath.replace(/'/g, "'\\''") + "'")
    }

    // Poll faster while the popup is open — that is the only time a stale second
    // is actually visible — and back off to the configured interval when closed.
    Timer {
        interval: root.expanded ? 1000 : Math.max(1, plasmoid.configuration.refreshInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 1000
        running: root.expanded
        repeat: true
        onTriggered: root.now = Date.now()
    }

    onExpandedChanged: {
        if (expanded) {
            now = Date.now()
            refresh()
            refreshUsage()
        } else {
            collapseAll()
        }
    }
}
