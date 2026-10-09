import QtQuick 2.15
import QtQuick.Templates 2.15 as T
T.ScrollBar {
    id: control
    implicitWidth: horizontal ? 80 : 10
    implicitHeight: horizontal ? 10 : 80
    padding: 2
    hoverEnabled: true
    minimumSize: 0.05
    contentItem: Rectangle {
        implicitWidth: 6
        implicitHeight: 6
        radius: 3
        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, control.hovered || control.pressed ? 0.45 : 0.28)
        opacity: control.policy === T.ScrollBar.AlwaysOn || control.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    background: Item {}
}
