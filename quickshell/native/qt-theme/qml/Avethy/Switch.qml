import QtQuick 2.15
import QtQuick.Templates 2.15 as T
T.Switch {
    id: control
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    padding: 4
    spacing: 8
    hoverEnabled: true
    indicator: Rectangle {
        implicitWidth: 42
        implicitHeight: 24
        x: control.mirrored ? control.width - width - control.rightPadding : control.leftPadding
        y: (control.height - height) / 2
        radius: 12
        color: control.checked ? (control.enabled ? Theme.primary : Theme.disabled.highlight) : Theme.hoverOverlay
        border.width: control.visualFocus ? 1 : 0
        border.color: Theme.primary
        Rectangle {
            x: 2 + control.visualPosition * (parent.width - width - 4)
            y: 2
            width: 20
            height: 20
            radius: 10
            color: control.checked ? Theme.primaryText : Theme.text
            Behavior on x { enabled: !control.down; NumberAnimation { duration: 120 } }
        }
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
