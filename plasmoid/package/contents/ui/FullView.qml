import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "../code/sessions.js" as Sessions

Item {
    id: full

    property var widget

    readonly property var shown: widget ? widget.shown : []
    readonly property var counts: widget ? widget.shownCounts : ({total: 0})
    readonly property string failure: widget ? widget.failure : ""
    readonly property bool loaded: widget ? widget.everLoaded : false

    Layout.minimumWidth: Kirigami.Units.gridUnit * 17
    Layout.minimumHeight: Kirigami.Units.gridUnit * 11
    Layout.preferredWidth: Kirigami.Units.gridUnit * 25
    Layout.preferredHeight: Kirigami.Units.gridUnit * 21

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PlasmaExtras.PlasmoidHeading {
            Layout.fillWidth: true

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaExtras.Heading {
                        level: 4
                        text: i18n("Claude Code")
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    // The headline does the work a row of count chips would, in
                    // words, and puts whatever is blocked first.
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: full.failure !== "" ? i18n("Can't read the session list")
                                                  : (full.loaded ? Sessions.headline(full.counts) : "")
                        color: full.failure !== "" ? Kirigami.Theme.negativeTextColor
                                                   : (full.counts.waiting
                                                      ? Kirigami.Theme.neutralTextColor
                                                      : Kirigami.Theme.disabledTextColor)
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                    }
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh-symbolic"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    text: i18n("Refresh now")
                    onClicked: full.widget.refresh()

                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            visible: full.shown.length > 0

            ListView {
                id: list
                model: full.shown
                spacing: 0
                clip: true
                reuseItems: true

                delegate: SessionRow {
                    required property var modelData
                    width: list.width
                    session: modelData
                    widget: full.widget
                    showProfile: full.widget ? full.widget.showProfiles : false
                }
            }
        }

        PlasmaExtras.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Kirigami.Units.largeSpacing
            visible: full.shown.length === 0 && (full.loaded || full.failure !== "")

            iconName: full.failure !== "" ? "dialog-error" : "dialog-messages"
            text: full.failure !== "" ? i18n("Can't read the session list")
                                      : i18n("No sessions running")
            explanation: full.failure !== "" ? full.failure
                                             : i18n("Open a terminal and run claude to start one.")
        }
    }
}
