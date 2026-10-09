import QtQuick
import QtQuick.Layouts
import "../components"

Rectangle {
    id: root
    property string label: ""
    property string icon: ""
    property bool accent: false
    property bool busy: false
    property bool danger: false
    signal clicked()
    implicitWidth: Math.max(36, content.implicitWidth + 24)
    implicitHeight: 36
    radius: height / 2
    color: accent ? Theme.colors.mauve
        : pointer.containsMouse ? Theme.popupSurface2 : Theme.popupSurface1
    opacity: enabled ? 1 : 0.45
    scale: pointer.pressed ? 0.96 : 1
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: if (enabled && !busy) clicked()
    Keys.onSpacePressed: if (enabled && !busy) clicked()
    Keys.onReturnPressed: if (enabled && !busy) clicked()
    border.width: activeFocus ? 2 : 0
    border.color: Theme.colors.mauve
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 6
        Text {
            visible: root.icon.length > 0 || root.busy
            text: root.busy ? "sync" : root.icon
            font.family: Theme.iconFamily
            font.pixelSize: 17
            color: root.accent ? Theme.colors.crust : root.danger ? Theme.colors.red : Theme.colors.text
            RotationAnimator on rotation { running: root.busy && root.visible; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
        }
        Text {
            visible: root.label.length > 0
            text: root.label
            color: root.accent ? Theme.colors.crust : root.danger ? Theme.colors.red : Theme.colors.text
            font.family: Theme.textFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled && !root.busy
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
