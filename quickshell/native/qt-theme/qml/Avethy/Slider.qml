import QtQuick 2.15
import QtQuick.Templates 2.15 as T
T.Slider {
    id: control
    implicitWidth: horizontal ? 200 : 24
    implicitHeight: horizontal ? 24 : 200
    padding: 8
    hoverEnabled: true
    background: Rectangle {
        x: control.horizontal ? control.leftPadding : (control.width - width) / 2
        y: control.horizontal ? (control.height - height) / 2 : control.topPadding
        width: control.horizontal ? control.availableWidth : 4
        height: control.horizontal ? 4 : control.availableHeight
        radius: 2
        color: Theme.hoverOverlay
        Rectangle {
            x: control.horizontal && control.mirrored ? parent.width - width : 0
            y: control.horizontal ? 0 : control.visualPosition * parent.height
            width: control.horizontal ? control.position * parent.width : parent.width
            height: control.horizontal ? parent.height : control.position * parent.height
            radius: 2
            color: control.enabled ? Theme.primary : Theme.disabled.highlight
        }
    }
    handle: Rectangle {
        x: control.horizontal ? control.leftPadding + control.visualPosition * (control.availableWidth - width) : (control.width - width) / 2
        y: control.horizontal ? (control.height - height) / 2 : control.topPadding + control.visualPosition * (control.availableHeight - height)
        implicitWidth: 16
        implicitHeight: 16
        radius: 8
        color: control.enabled ? Theme.primary : Theme.disabled.highlight
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.primaryText
    }
}
