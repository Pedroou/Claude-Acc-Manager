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

    readonly property color tone: widget ? widget.tone(session.state) : Kirigami.Theme.textColor
    readonly property double now: widget ? widget.now : Date.now()

    implicitHeight: body.implicitHeight + Kirigami.Units.smallSpacing * 2

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        radius: Math.round(Kirigami.Units.gridUnit / 4)
        color: Kirigami.Theme.highlightColor
        opacity: hover.containsMouse ? 0.13 : 0
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.detailsOpen = !row.detailsOpen
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
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: row.session.name
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: Sessions.context(row.session, row.showProfile)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                elide: Text.ElideMiddle
                maximumLineCount: 1
                visible: text !== ""
            }

            // Opened by clicking the row: the things you would otherwise go
            // hunting through `ps` for.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: row.detailsOpen ? Kirigami.Units.smallSpacing : 0
                spacing: 0
                visible: row.detailsOpen

                Repeater {
                    model: row.detailsOpen ? [
                        {key: i18n("Folder"), value: row.session.cwd},
                        {key: i18n("Session"), value: row.session.sessionId},
                        {key: i18n("Profile"), value: row.session.profile},
                        {key: i18n("Process"), value: String(row.session.pid)},
                        {key: i18n("Started"), value: Sessions.age(row.session.startedAt, row.now) + i18n(" ago")},
                        {key: i18n("Version"), value: row.session.version}
                    ] : []

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: modelData.value !== "" && modelData.value !== "0"

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

        ColumnLayout {
            spacing: 0
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)

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
