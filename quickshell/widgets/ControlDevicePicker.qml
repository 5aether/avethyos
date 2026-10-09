import QtQuick
import QtQuick.Layouts
import "../components"

ColumnLayout {
    id: root
    property string title: "Devices"
    property string emptyText: "No devices found"
    property var entries: []
    property var selectedId: null
    signal selected(var entry)
    spacing: 10
    Text {
        text: root.title
        color: Theme.colors.text
        font.family: Theme.textFamily
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: root.entries
        spacing: 4
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool chosen: modelData.id === root.selectedId
            width: ListView.view.width
            height: 54
            radius: 16
            color: chosen || pointer.containsMouse ? Theme.popupSurface2 : Theme.popupSurface1
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: modelData.label
            Accessible.onPressAction: root.selected(modelData)
            Keys.onReturnPressed: root.selected(modelData)
            Keys.onSpacePressed: root.selected(modelData)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10
                Text {
                    text: row.modelData.icon || "devices"
                    color: row.chosen ? Theme.colors.mauve : Theme.colors.textDim
                    font.family: Theme.iconFamily
                    font.pixelSize: 23
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        color: Theme.colors.text
                        font.family: Theme.textFamily
                        font.pixelSize: 11
                        font.weight: row.chosen ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.subtitle || (row.chosen ? "Selected" : "Available")
                        color: Theme.colors.textDim
                        font.family: Theme.textFamily
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }
                Text {
                    visible: row.chosen
                    text: "check_circle"
                    color: Theme.colors.mauve
                    font.family: Theme.iconFamily
                    font.pixelSize: 20
                }
            }
            MouseArea {
                id: pointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selected(row.modelData)
            }
        }
        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: root.emptyText
            color: Theme.colors.textDim
            font.family: Theme.textFamily
            font.pixelSize: 11
        }
    }
}
