import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/usage.js" as Usage

// One plan limit: a track, a fill coloured by how close it is, and the number.
// When there is nothing to draw, the message takes the whole width — a profile
// that is signed out should say so, not show an empty bar reading zero.
RowLayout {
    id: usage

    property var bar
    property string message: ""
    property double now: Date.now()

    readonly property string level: Usage.severity(bar)
    readonly property color fillColor: {
        switch (level) {
        case "critical": return Kirigami.Theme.negativeTextColor
        case "warning": return Kirigami.Theme.neutralTextColor
        default: return Kirigami.Theme.positiveTextColor
        }
    }

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: usage.bar === null || usage.message !== ""
        text: usage.message
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        elide: Text.ElideRight
    }

    PlasmaComponents3.Label {
        visible: usage.bar !== null && usage.message === ""
        text: usage.bar ? usage.bar.label : ""
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
    }

    // The track and the fill are siblings, not parent and child: opacity in QML
    // multiplies down, so a fill inside a faded track could never come out solid.
    Item {
        id: track
        visible: usage.bar !== null && usage.message === ""
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: Math.max(4, Math.round(Kirigami.Units.gridUnit / 3))

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Kirigami.Theme.textColor
            opacity: 0.15
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * Math.max(0, Math.min(100, usage.bar ? usage.bar.percent : 0)) / 100
            radius: height / 2
            color: usage.fillColor

            Behavior on width {
                NumberAnimation { duration: Kirigami.Units.longDuration }
            }
        }
    }

    PlasmaComponents3.Label {
        visible: usage.bar !== null && usage.message === ""
        text: usage.bar ? i18nc("percentage of a plan limit used", "%1%", usage.bar.percent) : ""
        font: Kirigami.Theme.smallFont
        color: usage.fillColor
        Layout.minimumWidth: Kirigami.Units.gridUnit * 1.6
        horizontalAlignment: Text.AlignRight

        HoverHandler {
            id: percentHover
        }

        PlasmaComponents3.ToolTip.text: usage.bar ? Usage.resetText(usage.bar.resetsAt, usage.now) : ""
        PlasmaComponents3.ToolTip.visible: percentHover.hovered
                                           && PlasmaComponents3.ToolTip.text !== ""
        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
}
