import QtQuick
import "../components"

Item {
    id: root
    property bool checked: false
    property string label: "Toggle"
    signal toggled(bool value)
    implicitWidth: 44
    implicitHeight: 32
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.45
    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.checked: checked
    Accessible.onToggleAction: if (enabled) toggled(!checked)
    Keys.onSpacePressed: if (enabled) toggled(!checked)
    Rectangle {
        anchors.centerIn: parent
        width: 42
        height: 26
        radius: 13
        color: root.checked ? Theme.colors.mauve : Theme.popupSurface2
        border.width: root.activeFocus ? 2 : 0
        border.color: Theme.colors.text
        Behavior on color { ColorAnimation { duration: 170 } }
        Rectangle {
            x: root.checked ? parent.width - width - 4 : 4
            anchors.verticalCenter: parent.verticalCenter
            width: pointer.pressed ? 22 : 18
            height: 18
            radius: 9
            color: root.checked ? Theme.colors.crust : Theme.colors.textDim
            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 130 } }
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled(!root.checked)
    }
}
