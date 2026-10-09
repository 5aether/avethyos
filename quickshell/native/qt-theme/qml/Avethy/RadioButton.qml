import QtQuick 2.15
import QtQuick.Templates 2.15 as T
T.RadioButton {
    id: control
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    implicitHeight: Math.max(28, implicitContentHeight + topPadding + bottomPadding)
    padding: 4
    spacing: 8
    hoverEnabled: true
    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        x: control.mirrored ? control.width - width - control.rightPadding : control.leftPadding
        y: (control.height - height) / 2
        radius: 9
        color: control.checked ? (control.enabled ? Theme.primary : Theme.disabled.highlight) : Theme.base
        border.width: control.checked ? 0 : 1
        border.color: control.visualFocus ? Theme.primary : Theme.border
        Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 4; color: Theme.primaryText; visible: control.checked }
    }
    contentItem: Text {
        leftPadding: control.mirrored ? 0 : control.indicator.width + control.spacing
        rightPadding: control.mirrored ? control.indicator.width + control.spacing : 0
        text: control.text
        font: control.font
        color: control.enabled ? Theme.text : Theme.disabled.windowText
        verticalAlignment: Text.AlignVCenter
    }
}
