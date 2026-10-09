import QtQuick 2.15
import QtQuick.Templates 2.15 as T
import QtQuick.Controls.impl 2.15
T.Button {
    id: control
    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    padding: 8
    horizontalPadding: 14
    spacing: 8
    hoverEnabled: true
    icon.width: 16
    icon.height: 16
    icon.color: !control.enabled ? Theme.disabled.buttonText
              : control.checked || control.highlighted ? Theme.primaryText : Theme.text
    contentItem: IconLabel {
        spacing: control.spacing
        mirrored: control.mirrored
        display: control.display
        icon: control.icon
        text: control.text
        font: control.font
        color: !control.enabled ? Theme.disabled.buttonText
             : control.checked || control.highlighted ? Theme.primaryText : Theme.text
    }
    background: Rectangle {
        implicitWidth: 80
        implicitHeight: 32
        radius: 8
        color: control.checked || control.highlighted ? (control.enabled ? Theme.primary : Theme.disabled.highlight)
             : control.flat ? (control.hovered || control.down ? Theme.hoverOverlay : "transparent")
             : control.hovered || control.down ? Theme.hover : Theme.button
        border.width: control.visualFocus || (!control.flat && !control.checked && !control.highlighted) ? 1 : 0
        border.color: control.visualFocus ? Theme.primary : Theme.border
    }
}
