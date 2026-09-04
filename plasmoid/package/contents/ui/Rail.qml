import QtQuick
import org.kde.kirigami as Kirigami

// One session, drawn as a bar. Colour says which state it is in; length says how
// much it wants your attention, so the two channels agree and either one alone is
// enough to read the widget.
Rectangle {
    id: rail

    property string sessionState: "unknown"
    property real fraction: 1.0
    property real track: Kirigami.Units.gridUnit
    property real thickness: 3
    property bool sideways: false // bars grow rightwards, for vertical panels

    readonly property real extent: Math.max(2, Math.round(track * fraction))

    implicitWidth: sideways ? extent : thickness
    implicitHeight: sideways ? thickness : extent
    width: implicitWidth
    height: implicitHeight
    radius: thickness / 2
    antialiasing: true

    // The one thing in the widget that moves on its own: a working session
    // breathes. Everything else holds still, so the movement means something.
    // Kirigami collapses its durations when the user turns animations off.
    SequentialAnimation on opacity {
        id: breathe
        running: rail.sessionState === "working" && Kirigami.Units.longDuration > 1
        loops: Animation.Infinite
        NumberAnimation { to: 0.42; duration: 950; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 950; easing.type: Easing.InOutSine }
    }

    Connections {
        target: breathe
        function onRunningChanged() {
            if (!breathe.running) {
                rail.opacity = 1.0
            }
        }
    }
}
