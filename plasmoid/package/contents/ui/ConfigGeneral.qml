import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_refreshInterval: interval.value
    property alias cfg_showDone: showDone.checked
    property alias cfg_attentionWhenWaiting: attention.checked

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
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        text: i18n("While the popup is open it always refreshes every second.")
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
        id: attention
        text: i18n("Highlight the widget when a session is waiting on me")
    }
}
