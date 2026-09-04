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
    property string failure: ""
    property double now: Date.now()
    // Until the first result lands there is nothing to say, and "No sessions
    // running" would be a guess rather than an answer.
    property bool everLoaded: false

    readonly property var shown: Sessions.visible(sessions, plasmoid.configuration)
    readonly property var shownCounts: Sessions.countsFor(shown)
    // The profile only earns space on a row when there is more than one in play.
    readonly property bool showProfiles: profiles.length > 1
                                         && sessions.some(function (s) { return s.profile === "personal" })

    // Colours come from the user's colour scheme rather than a palette of our
    // own, so the widget belongs to whatever theme the panel is wearing.
    function tone(state) {
        switch (state) {
        case "waiting":
            return Kirigami.Theme.neutralTextColor
        case "working":
            return Kirigami.Theme.highlightColor
        case "shell":
            return Kirigami.Theme.textColor
        case "done":
            return Kirigami.Theme.positiveTextColor
        default:
            return Kirigami.Theme.disabledTextColor
        }
    }

    compactRepresentation: CompactView { widget: root }
    fullRepresentation: FullView { widget: root }

    Plasmoid.status: {
        if (shownCounts.waiting > 0 && plasmoid.configuration.attentionWhenWaiting) {
            return PlasmaCore.Types.NeedsAttentionStatus
        }
        return shownCounts.total > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    }

    toolTipMainText: i18n("Claude Code")
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

    onExpandedChanged: if (expanded) {
        now = Date.now()
        refresh()
    }
}
