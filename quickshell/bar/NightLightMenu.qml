import QtQuick
import QtQuick.Layouts
import "../components"
import "../widgets"

ColumnLayout {
    id: root
    property bool active: true
    property real temperature: Config.nightLightTemperature
    implicitHeight: 320
    spacing: 16
    Connections {
        target: Config
        function onNightLightTemperatureChanged() {
            if (!temperatureSlider.dragging) root.temperature = Config.nightLightTemperature;
        }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 80
        radius: 22
        color: Theme.popupSurface0
        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            ControlSectionHeader {
                Layout.fillWidth: true
                title: "Easy on your eyes"
                subtitle: NightLightService.active ? "Your displays are warm" : "Warm your displays after dark"
                icon: "bedtime"
            }
            ControlSwitch {
                label: "Night light"
                checked: Config.nightLightEnabled
                enabled: NightLightService.available
                onToggled: value => NightLightService.setEnabled(value)
            }
        }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 156
        radius: 22
        color: Theme.popupSurface0
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Color temperature"; font.family: Theme.textFamily; font.pixelSize: 12; color: Theme.colors.text }
                Item { Layout.fillWidth: true }
                Text { text: Math.round(root.temperature) + " K"; font.family: Theme.textFamily; font.pixelSize: 11; color: Theme.colors.textDim }
            }
            ControlSlider {
                id: temperatureSlider
                Layout.fillWidth: true
                minimum: 1000
                maximum: 6500
                step: 100
                value: root.temperature
                valueText: Math.round(root.temperature) + " K"
                icon: "wb_sunny"
                label: "Night light temperature"
                accent: Theme.colors.yellow
                enabled: NightLightService.available
                onMoved: value => root.temperature = value
                onCommitted: value => NightLightService.setTemperature(value)
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [{name: "Warm", value: 2500}, {name: "Cozy", value: 3500}, {name: "Soft", value: 4500}, {name: "Neutral", value: 6500}]
                    ControlButton {
                        required property var modelData
                        Layout.fillWidth: true
                        label: modelData.name
                        accent: Math.abs(root.temperature - modelData.value) < 50
                        enabled: NightLightService.available
                        onClicked: NightLightService.setTemperature(modelData.value)
                    }
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: NightLightService.error || "Screenshots and screen sharing keep their original colors."
        color: NightLightService.error.length ? Theme.colors.red : Theme.colors.textDim
        font.family: Theme.textFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
    Item { Layout.fillHeight: true }
}
