import QtQuick 2.15
import QtQuick.Templates 2.15 as T
import QtQuick.Controls.impl 2.15
T.ToolButton {
    id: control
    implicitWidth: Math.max(32, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    padding: 8
    spacing: 6
    hoverEnabled: true
    icon.width: 16
    icon.height: 16
    icon.color: !control.enabled ? Theme.disabled.buttonText : control.checked ? Theme.primaryText : Theme.text
    contentItem: IconLabel {
        spacing: control.spacing
        mirrored: control.mirrored
        display: control.display
        icon: control.icon
        text: control.text
        font: control.font
        color: !control.enabled ? Theme.disabled.buttonText : control.checked ? Theme.primaryText : Theme.text
    }
    background: Rectangle {
        radius: 8
        color: control.checked ? Theme.primary : control.hovered || control.down ? Theme.hoverOverlay : "transparent"
        border.width: control.visualFocus ? 1 : 0
        border.color: Theme.primary
    }
}
