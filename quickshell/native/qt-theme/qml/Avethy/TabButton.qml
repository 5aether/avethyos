import QtQuick 2.15
import QtQuick.Templates 2.15 as T
import QtQuick.Controls.impl 2.15
T.TabButton {
    id: control
    implicitWidth: Math.max(80, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    padding: 8
    horizontalPadding: 14
    spacing: 8
    hoverEnabled: true
    icon.width: 16
    icon.height: 16
    icon.color: Theme.text
    contentItem: IconLabel {
        spacing: control.spacing
        mirrored: control.mirrored
        display: control.display
        icon: control.icon
        text: control.text
        font: control.font
        color: control.enabled ? Theme.text : Theme.disabled.buttonText
    }
    background: Rectangle {
        radius: 8
        color: control.checked || control.hovered ? Theme.hoverOverlay : "transparent"
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 24
            height: 2
            radius: 1
            color: Theme.primary
            visible: control.checked
        }
    }
}
