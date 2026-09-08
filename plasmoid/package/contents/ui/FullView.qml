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
    readonly property bool censored: widget ? widget.censored : false

    readonly property int maxHeight: Kirigami.Units.gridUnit * plasmoid.configuration.maxPopupHeight

    Layout.minimumWidth: Kirigami.Units.gridUnit * 17
    Layout.minimumHeight: Kirigami.Units.gridUnit * 8
    Layout.preferredWidth: Kirigami.Units.gridUnit * 25
    Layout.maximumHeight: maxHeight

    // The popup is as tall as its sessions need and no taller, up to the ceiling
    // in settings — past which the list scrolls instead of the window growing.
    Layout.preferredHeight: Math.min(maxHeight,
                                     header.implicitHeight
                                     + (full.shown.length > 0
                                        ? list.contentHeight + Kirigami.Units.smallSpacing * 2
                                        : Kirigami.Units.gridUnit * 7)
                                     + footer.implicitHeight)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PlasmaExtras.PlasmoidHeading {
            id: header
            Layout.fillWidth: true

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaExtras.Heading {
                        level: 4
                        text: i18n("Claude Code Sessions")
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    // The headline does the work a row of count chips would, in
                    // words, and puts whatever is blocked first. Each count wears
                    // its own status colour so the sentence is scannable.
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        textFormat: Text.StyledText
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.disabledTextColor
                        text: {
                            if (full.failure !== "") {
                                return i18n("Can't read the session list")
                            }
                            if (!full.loaded) {
                                return ""
                            }
                            if (!full.counts.total) {
                                return i18n("Nothing running")
                            }
                            var parts = Sessions.summaryParts(full.counts)
                            return parts.map(function (p) {
                                var colour = String(full.widget.tone(p.state))
                                return "<font color=\"" + colour + "\">" + p.count + "</font> " + p.noun
                            }).join(", ")
                        }
                    }
                }

                PlasmaComponents3.ToolButton {
                    icon.name: full.censored ? "view-hidden" : "view-visible"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    checkable: true
                    checked: full.censored
                    text: full.censored ? i18n("Show session names") : i18n("Hide session names")
                    onClicked: plasmoid.configuration.censorNames = !plasmoid.configuration.censorNames

                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                PlasmaComponents3.ToolButton {
                    icon.source: Qt.resolvedUrl("../icons/reload.svg")
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
                // Rows keep per-session state (expanded, renaming), so recycling
                // one would hand that state to a different session.
                reuseItems: false

                delegate: SessionRow {
                    required property var modelData
                    width: list.width
                    session: modelData
                    widget: full.widget
                    showProfile: full.widget ? full.widget.showProfiles : false
                }
            }
        }

        ProfileFooter {
            id: footer
            Layout.fillWidth: true
            widget: full.widget
            visible: plasmoid.configuration.showUsage
                     && full.widget && full.widget.usage !== null
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
