import QtQuick 2.15
import QtQuick.Templates 2.15 as T
T.ProgressBar {
    id: control
    implicitWidth: 200
    implicitHeight: 4
    contentItem: Item {
        clip: true
        Rectangle {
            width: control.indeterminate ? parent.width * 0.35 : control.position * parent.width
            height: parent.height
            radius: 2
            color: control.enabled ? Theme.primary : Theme.disabled.highlight
            x: control.mirrored ? parent.width - width : 0
            SequentialAnimation on x {
                running: control.indeterminate && control.visible
                loops: Animation.Infinite
                NumberAnimation { from: -control.width * 0.35; to: control.width; duration: 1100 }
            }
        }
    }
    background: Rectangle { radius: 2; color: Theme.hoverOverlay }
}
