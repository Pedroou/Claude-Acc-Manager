import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/sessions.js" as Sessions

// The panel only has to answer one question: is anything waiting on me? So the
// sessions are drawn as a small bar chart — one bar each, tallest when a session
// is blocked — with the running total beside it.
MouseArea {
    id: compact

    property var widget

    readonly property bool sideways: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property var shown: widget ? widget.shown : []
    readonly property var counts: widget ? widget.shownCounts : ({total: 0})
    readonly property bool failed: widget ? widget.failure !== "" : false

    // Past a point the bars stop being countable and the number carries the load.
    readonly property int maxRails: 8
    readonly property var railed: shown.slice(0, maxRails)

    readonly property real thickness: Math.max(2, Math.round(Kirigami.Units.smallSpacing * 0.8))
    readonly property real gap: Math.max(2, Math.round(thickness * 0.9))
    readonly property real track: Math.max(Kirigami.Units.iconSizes.small,
                                           (sideways ? compact.width : compact.height)
                                           - Kirigami.Units.smallSpacing * 2)

    function tone(state) {
        return widget ? widget.tone(state) : Kirigami.Theme.disabledTextColor
    }

    activeFocusOnTab: true
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    Accessible.role: Accessible.Button
    Accessible.name: i18n("Claude Code sessions")
    Accessible.description: Sessions.tooltipLines(compact.counts).replace(/\n/g, ", ")
    Accessible.onPressAction: widget.expanded = !widget.expanded

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) {
            widget.refresh()
        } else {
            widget.expanded = !widget.expanded
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            widget.expanded = !widget.expanded
            event.accepted = true
        }
    }

    Layout.minimumWidth: sideways ? 0 : content.implicitWidth
    Layout.minimumHeight: sideways ? content.implicitHeight : 0
    Layout.preferredWidth: sideways ? compact.width : content.implicitWidth
    Layout.preferredHeight: sideways ? content.implicitHeight : compact.height

    GridLayout {
        id: content
        anchors.centerIn: parent
        flow: compact.sideways ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        // The bars, baseline-aligned so the different heights read as a chart.
        GridLayout {
            id: cluster
            flow: compact.sideways ? GridLayout.TopToBottom : GridLayout.LeftToRight
            columnSpacing: compact.gap
            rowSpacing: compact.gap
            Layout.alignment: compact.sideways ? Qt.AlignLeft | Qt.AlignVCenter
                                               : Qt.AlignBottom | Qt.AlignHCenter

            Repeater {
                model: compact.railed
                delegate: Rail {
                    required property var modelData
                    sessionState: modelData.state
                    fraction: Sessions.railFraction(modelData.state)
                    color: compact.tone(modelData.state)
                    track: compact.track
                    thickness: compact.thickness
                    sideways: compact.sideways
                    Layout.alignment: compact.sideways ? Qt.AlignLeft | Qt.AlignVCenter
                                                       : Qt.AlignBottom | Qt.AlignHCenter
                }
            }

            // Nothing running: one faint tick, so the widget reads as quiet
            // rather than broken.
            Rail {
                visible: compact.railed.length === 0
                sessionState: "none"
                fraction: 0.14
                color: compact.failed ? Kirigami.Theme.negativeTextColor
                                      : Kirigami.Theme.disabledTextColor
                track: compact.track
                thickness: compact.thickness
                sideways: compact.sideways
                Layout.alignment: compact.sideways ? Qt.AlignLeft | Qt.AlignVCenter
                                                   : Qt.AlignBottom | Qt.AlignHCenter
            }
        }

        PlasmaComponents3.Label {
            visible: compact.counts.total > 0
            text: compact.counts.total
            color: compact.tone(Sessions.dominantState(compact.counts))
            // Scales with the panel, but stops growing before it starts
            // shouting on a tall dock.
            font.pixelSize: Math.max(Math.round(Kirigami.Units.gridUnit * 0.6),
                                     Math.min(Math.round(compact.track * 0.6),
                                              Kirigami.Units.gridUnit))
            font.weight: Font.DemiBold
            Layout.alignment: Qt.AlignCenter
        }
    }
}
