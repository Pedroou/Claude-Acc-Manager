import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "../code/usage.js" as Usage

// How much of the plan each account has used. Collapsed it shows the one profile
// you picked; expanded, both — because the reason to open it is to compare them.
ColumnLayout {
    id: footer

    property var widget

    readonly property var usage: widget ? widget.usage : null
    readonly property bool expanded: plasmoid.configuration.usageExpanded
    readonly property string selected: plasmoid.configuration.usageProfile
    readonly property var profiles: Usage.selectableProfiles(usage)

    spacing: 0

    function barIdFor(profileId) {
        return profileId === "personal"
            ? plasmoid.configuration.usageBarPersonal
            : plasmoid.configuration.usageBarWork
    }

    function setBarFor(profileId, barId) {
        if (profileId === "personal") {
            plasmoid.configuration.usageBarPersonal = barId
        } else {
            plasmoid.configuration.usageBarWork = barId
        }
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    Repeater {
        model: footer.profiles

        delegate: Item {
            id: profileRow
            required property var modelData

            // Collapsed, only the chosen profile is on screen; the others are
            // one click away rather than gone.
            readonly property bool isSelected: modelData.id === footer.selected
            visible: footer.expanded || isSelected

            Layout.fillWidth: true
            implicitHeight: line.implicitHeight + Kirigami.Units.smallSpacing * 2

            readonly property var bar: Usage.barFor(modelData, footer.barIdFor(modelData.id))
            readonly property string message: Usage.stateMessage(modelData)

            Rectangle {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing / 2
                radius: Math.round(Kirigami.Units.gridUnit / 4)
                color: Kirigami.Theme.textColor
                opacity: rowHover.hovered ? 0.09 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Kirigami.Units.shortDuration }
                }
            }

            HoverHandler {
                id: rowHover
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    // Picking a profile that is already showing collapses the
                    // list again; picking another one selects it.
                    if (!footer.expanded) {
                        plasmoid.configuration.usageExpanded = true
                    } else if (profileRow.isSelected) {
                        plasmoid.configuration.usageExpanded = false
                    } else {
                        plasmoid.configuration.usageProfile = profileRow.modelData.id
                        plasmoid.configuration.usageExpanded = false
                    }
                }
            }

            RowLayout {
                id: line
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Kirigami.Units.smallSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: footer.expanded ? "go-down-symbolic" : "go-next-symbolic"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                    opacity: profileRow.isSelected ? 1 : 0
                    Layout.alignment: Qt.AlignVCenter
                }

                PlasmaComponents3.Label {
                    text: profileRow.modelData.id
                    // Piecemeal: assigning the whole `font` group and one of its
                    // members in the same object is a QML error.
                    font.family: Kirigami.Theme.smallFont.family
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.weight: profileRow.isSelected ? Font.DemiBold : Font.Normal
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 3.5
                    Layout.alignment: Qt.AlignVCenter
                }

                // The bar-type picker. It sits on every row, including the ones
                // not currently selected, so you can set them up without
                // switching to them first.
                PlasmaComponents3.ToolButton {
                    icon.name: "go-next-symbolic"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    flat: true
                    enabled: profileRow.modelData.bars.length > 0
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                    text: i18n("Choose which limit to show")
                    onClicked: barMenu.open()

                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

                    PlasmaComponents3.Menu {
                        id: barMenu
                        y: parent.height

                        Repeater {
                            model: profileRow.modelData.bars
                            delegate: PlasmaComponents3.MenuItem {
                                required property var modelData
                                text: modelData.label
                                checkable: true
                                checked: modelData.id === footer.barIdFor(profileRow.modelData.id)
                                onTriggered: footer.setBarFor(profileRow.modelData.id, modelData.id)
                            }
                        }
                    }
                }

                UsageBar {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    bar: profileRow.bar
                    message: profileRow.message
                    now: footer.widget ? footer.widget.now : Date.now()
                }
            }
        }
    }
}
