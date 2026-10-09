import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../components"

Rectangle {
    id: root
    property string label: ""
    property string subtitle: ""
    property string icon: ""
    property url thumbnail: ""
    property bool checked: false
    property bool expandable: false
    property bool showSwitch: true
    property bool toggleAvailable: true
    signal toggled(bool value)
    signal expansionRequested()
    implicitHeight: 94
    implicitWidth: 180
    Layout.fillWidth: true
    radius: 22
    color: pointer.containsMouse ? Theme.popupSurface1 : Theme.popupSurface0
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? Theme.colors.mauve
        : checked ? Qt.rgba(Theme.colors.mauve.r, Theme.colors.mauve.g, Theme.colors.mauve.b, 0.22) : "transparent"
    scale: pointer.pressed ? 0.975 : 1
    activeFocusOnTab: true
    Accessible.role: expandable ? Accessible.Button : Accessible.CheckBox
    Accessible.name: label + ", " + subtitle
    Accessible.checked: checked
    Accessible.onPressAction: expandable ? expansionRequested() : toggled(!checked)
    Accessible.onToggleAction: if (toggleAvailable) toggled(!checked)
    Keys.onSpacePressed: expandable ? expansionRequested() : toggled(!checked)
    Keys.onReturnPressed: expandable ? expansionRequested() : toggled(!checked)
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 180 } }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expandable ? root.expansionRequested() : root.toggled(!root.checked)
    }
    ClippingRectangle {
        x: 12
        y: 10
        width: root.thumbnail.toString().length ? 56 : 34
        height: 34
        radius: root.thumbnail.toString().length ? 10 : 17
        color: root.checked ? Theme.colors.mauve : Theme.popupSurface2
        contentUnderBorder: true
        Image {
            id: preview
            anchors.fill: parent
            source: root.thumbnail
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
        }
        Text {
            anchors.centerIn: parent
            visible: preview.status !== Image.Ready
            text: root.icon
            color: root.checked ? Theme.colors.crust : Theme.colors.textDim
            font.family: Theme.iconFamily
            font.pixelSize: 20
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.toggleAvailable && root.showSwitch
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.toggled(!root.checked)
        }
    }
    ControlSwitch {
        anchors.right: parent.right
        anchors.rightMargin: 9
        y: 10
        visible: root.showSwitch
        enabled: root.toggleAvailable
        checked: root.checked
        label: root.label
        onToggled: value => root.toggled(value)
    }
    Column {
        x: 13
        y: 52
        width: parent.width - 36
        spacing: 3
        Text {
            width: parent.width
            text: root.label
            color: Theme.colors.text
            font.family: Theme.textFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: root.subtitle
            color: Theme.colors.textDim
            font.family: Theme.textFamily
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 10
        y: 60
        visible: root.expandable
        text: "chevron_right"
        color: Theme.colors.textDim
        font.family: Theme.iconFamily
        font.pixelSize: 19
    }
}
