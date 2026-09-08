import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/sessions.js" as Sessions

// One session. The rail on the left is the same device the panel uses, so the
// popup reads as the panel opened up rather than as a different screen.
Item {
    id: row

    property var session
    property var widget
    property bool showProfile: false
    property bool detailsOpen: false
    property bool renaming: false
    // Ending a session is one click away from losing what it was doing, so the
    // button asks once. The timer puts it back if the answer never comes.
    property bool confirmingEnd: false

    readonly property color tone: widget ? widget.tone(session.state) : Kirigami.Theme.textColor
    readonly property double now: widget ? widget.now : Date.now()
    readonly property bool censored: widget ? widget.censored : false
    readonly property string name: widget
        ? Sessions.displayName(session, widget.nicknames, censored)
        : session.name
    readonly property var rows: Sessions.detailRows(session, plasmoid.configuration, now, censored)

    implicitHeight: body.implicitHeight + Kirigami.Units.smallSpacing * 2

    Connections {
        target: row.widget
        function onCollapseAll() {
            row.detailsOpen = false
            row.renaming = false
            row.confirmingEnd = false
        }
    }

    Timer {
        id: confirmTimeout
        interval: 4000
        onTriggered: row.confirmingEnd = false
    }
    onConfirmingEndChanged: if (confirmingEnd) {
        confirmTimeout.restart()
    } else {
        confirmTimeout.stop()
    }

    // Tracks the whole row including its buttons, so reaching for one does not
    // make the others vanish out from under the pointer.
    HoverHandler {
        id: rowHover
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        radius: Math.round(Kirigami.Units.gridUnit / 4)
        // A neutral wash rather than the theme accent: the accent is a colour,
        // and every colour in this row already means something.
        color: Kirigami.Theme.textColor
        opacity: rowHover.hovered ? 0.09 : 0
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                // Collapsed, the useful thing to paste is the way back in.
                // Expanded, it is everything on screen.
                row.widget.copyToClipboard(row.detailsOpen
                    ? Sessions.detailsAsText(row.session, plasmoid.configuration,
                                             row.now, row.widget.nicknames, row.censored)
                    : Sessions.resumeCommand(row.session))
            } else {
                row.detailsOpen = !row.detailsOpen
            }
        }
    }

    RowLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Rail {
            sessionState: row.session.state
            fraction: 1.0
            color: row.tone
            thickness: 3
            track: headings.implicitHeight
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            id: headings
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: row.name
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: !row.renaming
            }

            PlasmaComponents3.TextField {
                id: renameField
                Layout.fillWidth: true
                visible: row.renaming
                placeholderText: row.session.name
                onAccepted: {
                    row.widget.setNickname(row.session.sessionId, text.trim())
                    row.renaming = false
                }
                Keys.onEscapePressed: row.renaming = false
                onVisibleChanged: if (visible) {
                    text = row.widget.nicknames[row.session.sessionId] || ""
                    forceActiveFocus()
                    selectAll()
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: Sessions.context(row.session, row.showProfile, row.censored)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                elide: Text.ElideMiddle
                maximumLineCount: 1
                visible: text !== "" && !row.renaming
            }

            // Opened by clicking the row: the things you would otherwise go
            // hunting through `ps` for. Click a value to copy it.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: row.detailsOpen ? Kirigami.Units.smallSpacing : 0
                spacing: 0
                visible: row.detailsOpen

                Repeater {
                    model: row.detailsOpen ? row.rows : []

                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: detailLine.implicitHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.rightMargin: Kirigami.Units.smallSpacing
                            radius: Math.round(Kirigami.Units.gridUnit / 6)
                            color: Kirigami.Theme.textColor
                            opacity: detailHover.hovered && modelData.copyable ? 0.09 : 0
                        }

                        HoverHandler {
                            id: detailHover
                            cursorShape: modelData.copyable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.copyable
                            onClicked: row.widget.copyToClipboard(modelData.value)
                        }

                        RowLayout {
                            id: detailLine
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents3.Label {
                                text: modelData.key
                                font: Kirigami.Theme.smallFont
                                color: Kirigami.Theme.disabledTextColor
                                Layout.minimumWidth: Kirigami.Units.gridUnit * 3.5
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: modelData.value
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideMiddle
                                maximumLineCount: 1
                            }
                        }
                    }
                }
            }
        }

        // Only on hover, and sitting before the status so the status never moves.
        //
        // There is no "interrupt" button here on purpose. Claude Code handles
        // Ctrl+C by reading the byte off a raw-mode terminal, not as a signal;
        // its actual SIGINT handler calls the same shutdown(0) as SIGTERM. So a
        // signal cannot pause a session, only end it, and a button labelled
        // "interrupt" that quietly ended sessions would be worse than none.
        RowLayout {
            spacing: 0
            Layout.alignment: Qt.AlignVCenter
            visible: rowHover.hovered && !row.renaming

            PlasmaComponents3.ToolButton {
                icon.name: "edit-rename"
                display: PlasmaComponents3.AbstractButton.IconOnly
                flat: true
                text: i18n("Rename in this widget")
                onClicked: row.renaming = true

                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PlasmaComponents3.ToolButton {
                icon.name: row.confirmingEnd ? "dialog-warning" : "window-close"
                display: PlasmaComponents3.AbstractButton.IconOnly
                flat: true
                icon.color: row.confirmingEnd ? Kirigami.Theme.negativeTextColor : undefined
                text: row.confirmingEnd ? i18n("Click again to end this session")
                                        : i18n("End this session")
                onClicked: {
                    if (row.confirmingEnd) {
                        row.widget.endSession(row.session.pid)
                        row.confirmingEnd = false
                    } else {
                        row.confirmingEnd = true
                    }
                }

                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 0
            }
        }

        ColumnLayout {
            spacing: 0
            Layout.alignment: Qt.AlignVCenter

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignRight
                text: row.session.label
                color: row.tone
                // Set piecemeal: assigning the whole `font` group and one of its
                // members in the same object is a QML error.
                font.family: Kirigami.Theme.smallFont.family
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.weight: Font.DemiBold
            }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignRight
                text: Sessions.age(row.session.statusUpdatedAt, row.now)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                visible: text !== ""
            }
        }
    }
}
