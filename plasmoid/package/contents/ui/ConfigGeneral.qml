import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

import "../code/sessions.js" as Sessions

Kirigami.FormLayout {
    id: page

    property alias cfg_refreshInterval: interval.value
    property alias cfg_maxPopupHeight: popupHeight.value
    property alias cfg_showDone: showDone.checked
    property alias cfg_attentionWhenWaiting: attention.checked
    property alias cfg_showTotal: showTotal.checked
    property alias cfg_showUsage: showUsage.checked

    property alias cfg_customColors: customColors.checked
    property alias cfg_colorWaiting: waitingColor.color
    property alias cfg_colorError: errorColor.color
    property alias cfg_colorRunning: runningColor.color
    property alias cfg_colorWorking: workingColor.color
    property alias cfg_colorShell: shellColor.color
    property alias cfg_colorDone: doneColor.color

    property alias cfg_detailRepository: detailRepository.checked
    property alias cfg_detailBranch: detailBranch.checked
    property alias cfg_detailSession: detailSession.checked
    property alias cfg_detailProcess: detailProcess.checked
    property alias cfg_detailVersion: detailVersion.checked
    property alias cfg_branchSeparate: branchSeparate.checked
    property alias cfg_shortLabels: shortLabels.checked

    property alias cfg_censorNames: censorNames.checked

    // Not edited on this page — the popup owns them — but declared so the reset
    // button below can put them back with everything else.
    property string cfg_nicknames: "{}"
    property string cfg_usageProfile: "work"
    property bool cfg_usageExpanded: false
    property string cfg_usageBarWork: "session"
    property string cfg_usageBarPersonal: "session"

    // Plasma's config dialog has no Defaults button of its own for an applet, so
    // the widget provides one. Everything below is written from one place, which
    // is also the list the dialog compares against to enable its Apply button.
    function resetToDefaults() {
        interval.value = 5
        popupHeight.value = 21
        showDone.checked = true
        attention.checked = true
        showTotal.checked = true
        showUsage.checked = true

        customColors.checked = false
        waitingColor.color = Sessions.defaultColor("waiting")
        errorColor.color = Sessions.defaultColor("error")
        runningColor.color = Sessions.defaultColor("running")
        workingColor.color = Sessions.defaultColor("working")
        shellColor.color = Sessions.defaultColor("shell")
        doneColor.color = Sessions.defaultColor("done")

        detailRepository.checked = true
        detailBranch.checked = true
        detailSession.checked = true
        detailProcess.checked = true
        detailVersion.checked = true
        branchSeparate.checked = false
        shortLabels.checked = false

        censorNames.checked = false
        page.cfg_nicknames = "{}"
        page.cfg_usageProfile = "work"
        page.cfg_usageExpanded = false
        page.cfg_usageBarWork = "session"
        page.cfg_usageBarPersonal = "session"
    }

    RowLayout {
        QQC2.Button {
            icon.name: "edit-undo"
            text: i18n("Reset everything to defaults")
            onClicked: page.resetToDefaults()
        }
        QQC2.Label {
            text: i18n("Applies when you press OK or Apply.")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        id: interval
        Kirigami.FormData.label: i18n("Check every:")
        from: 1
        to: 60
        stepSize: 1
        textFromValue: function (value) {
            return i18np("%1 second", "%1 seconds", value)
        }
        valueFromText: function (text) {
            return parseInt(text, 10)
        }
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        text: i18n("While the popup is open it always refreshes every second.")
    }

    QQC2.SpinBox {
        id: popupHeight
        Kirigami.FormData.label: i18n("Tallest the popup gets:")
        from: 8
        to: 60
        stepSize: 1
        textFromValue: function (value) {
            return i18np("%1 line", "%1 lines", value)
        }
        valueFromText: function (text) {
            return parseInt(text, 10)
        }
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        text: i18n("Fewer sessions make a shorter popup. More than this and it scrolls.")
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: showDone
        Kirigami.FormData.label: i18n("Show:")
        text: i18n("Sessions that are done")
    }

    QQC2.CheckBox {
        id: showTotal
        text: i18n("The session count in the panel")
    }

    QQC2.CheckBox {
        id: attention
        text: i18n("Highlight the widget when a session is waiting on me")
    }

    QQC2.CheckBox {
        id: showUsage
        text: i18n("Plan usage for each profile")
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        text: i18n("The only part of the widget that uses the network. It asks Anthropic for your plan limits every five minutes, with the login Claude Code already has.")
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: customColors
        Kirigami.FormData.label: i18n("Colours:")
        text: i18n("Customize status colours")
    }

    // Hidden rather than disabled while the checkbox is off: leaving the pickers
    // on screen would suggest the colours in them were still in force. They keep
    // their values, but nothing reads them until the box is ticked again.
    RowLayout {
        Kirigami.FormData.label: i18n("Waiting:")
        visible: customColors.checked
        spacing: Kirigami.Units.smallSpacing

        KQuickControls.ColorButton {
            id: waitingColor
            showAlphaChannel: false
            dialogTitle: i18n("Colour for waiting sessions")
        }

        QQC2.Button {
            icon.name: "edit-undo"
            flat: true
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Use the built-in colour")
            onClicked: waitingColor.color = Sessions.defaultColor("waiting")

            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Error:")
        visible: customColors.checked
        spacing: Kirigami.Units.smallSpacing

        KQuickControls.ColorButton {
            id: errorColor
            showAlphaChannel: false
            dialogTitle: i18n("Colour for error sessions")
        }

        QQC2.Button {
            icon.name: "edit-undo"
            flat: true
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Use the built-in colour")
            onClicked: errorColor.color = Sessions.defaultColor("error")

            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Running:")
        visible: customColors.checked
        spacing: Kirigami.Units.smallSpacing

        KQuickControls.ColorButton {
            id: runningColor
            showAlphaChannel: false
            dialogTitle: i18n("Colour for running sessions")
        }

        QQC2.Button {
            icon.name: "edit-undo"
            flat: true
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Use the built-in colour")
            onClicked: runningColor.color = Sessions.defaultColor("running")

            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Working:")
        visible: customColors.checked
        spacing: Kirigami.Units.smallSpacing

        KQuickControls.ColorButton {
            id: workingColor
            showAlphaChannel: false
            dialogTitle: i18n("Colour for working sessions")
        }

        QQC2.Button {
            icon.name: "edit-undo"
            flat: true
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Use the built-in colour")
            onClicked: workingColor.color = Sessions.defaultColor("working")

            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Shell:")
        visible: customColors.checked
        spacing: Kirigami.Units.smallSpacing

        KQuickControls.ColorButton {
            id: shellColor
            showAlphaChannel: false
            dialogTitle: i18n("Colour for shell sessions")
        }

        QQC2.Button {
            icon.name: "edit-undo"
            flat: true
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Use the built-in colour")
            onClicked: shellColor.color = Sessions.defaultColor("shell")

            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Done:")
        visible: customColors.checked
        spacing: Kirigami.Units.smallSpacing

        KQuickControls.ColorButton {
            id: doneColor
            showAlphaChannel: false
            dialogTitle: i18n("Colour for done sessions")
        }

        QQC2.Button {
            icon.name: "edit-undo"
            flat: true
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Use the built-in colour")
            onClicked: doneColor.color = Sessions.defaultColor("done")

            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: detailRepository
        Kirigami.FormData.label: i18n("Session details:")
        text: i18n("Repository")
    }

    QQC2.CheckBox {
        id: detailBranch
        text: i18n("Branch")
    }

    QQC2.CheckBox {
        id: branchSeparate
        text: i18n("…on its own row, not appended to the repository")
        enabled: detailBranch.checked
        Layout.leftMargin: Kirigami.Units.gridUnit
    }

    QQC2.CheckBox {
        id: detailSession
        text: i18n("Session")
    }

    QQC2.CheckBox {
        id: detailProcess
        text: i18n("Process")
    }

    QQC2.CheckBox {
        id: detailVersion
        text: i18n("Version")
    }

    QQC2.CheckBox {
        id: shortLabels
        text: i18n("Shorten “Directory” and “Repository” to “Dir” and “Repo”")
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: censorNames
        Kirigami.FormData.label: i18n("Privacy:")
        text: i18n("Hide session names and paths")
    }
}
