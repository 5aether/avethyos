import QtQuick
import QtQuick.Layouts
import "../components"

RowLayout {
    id: root
    property string title: ""
    property string subtitle: ""
    property string icon: ""
    spacing: 10
    Text {
        visible: root.icon.length > 0
        text: root.icon
        color: Theme.colors.mauve
        font.family: Theme.iconFamily
        font.pixelSize: 23
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        Text {
            Layout.fillWidth: true
            text: root.title
            color: Theme.colors.text
            font.family: Theme.textFamily
            font.pixelSize: 16
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: root.subtitle.length > 0
            text: root.subtitle
            color: Theme.colors.textDim
            font.family: Theme.textFamily
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
}
