import QtQuick 2.15
import QtQuick.Templates 2.15 as T
import QtQuick.Controls.impl 2.15
T.ItemDelegate {
    id: control
    implicitWidth: Math.max(implicitContentWidth + leftPadding + rightPadding, 100)
    implicitHeight: Math.max(36, implicitContentHeight + topPadding + bottomPadding)
    padding: 8
    horizontalPadding: 12
    spacing: 8
    hoverEnabled: true
    icon.width: 16
    icon.height: 16
    icon.color: control.highlighted ? Theme.primaryText : control.enabled ? Theme.text : Theme.disabled.windowText
    contentItem: IconLabel {
        spacing: control.spacing
        mirrored: control.mirrored
        display: control.display
        icon: control.icon
        text: control.text
        font: control.font
        alignment: Qt.AlignLeft
        color: control.highlighted ? Theme.primaryText : control.enabled ? Theme.text : Theme.disabled.windowText
    }
    background: Rectangle {
        radius: 7
        color: control.highlighted ? Theme.primary : control.hovered || control.down ? Theme.hoverOverlay : "transparent"
    }
}
