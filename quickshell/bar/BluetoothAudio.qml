import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../components"
import "../widgets"

// Displays volume and bluetooth icon when using a bluetooth audio device
Item {
    id: root

    // Check if the current audio output is a bluetooth device
    readonly property bool isBluetoothAudio: {
        if (!AudioService.output || !AudioService.output.description)
            return false;
        const desc = AudioService.output.description.toLowerCase();
        // Common bluetooth device indicators in PipeWire node descriptions
        return desc.includes("bluetooth") || desc.includes("bluez");
    }

    visible: isBluetoothAudio
    implicitWidth: isBluetoothAudio ? volumeRow.width : 0
    implicitHeight: 30

    Behavior on implicitWidth {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    Row {
        id: volumeRow
        anchors.centerIn: parent
        spacing: 6
        opacity: root.isBluetoothAudio ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        // Bluetooth icon
        Text {
            width: 18
            height: 26
            text: "bluetooth_audio"
            color: Theme.colors.blue
            font.family: Theme.iconFamily
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // Volume percentage
        Text {
            height: 26
            text: Math.round(AudioService.volume * 100) + "%"
            color: Theme.colors.text
            font.family: Theme.textFamily
            font.pixelSize: 12
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // Volume icon
        Text {
            width: 18
            height: 26
            text: AudioService.muted || AudioService.volume <= 0
                ? "volume_off" : AudioService.volume < 0.5 ? "volume_down" : "volume_up"
            color: AudioService.muted ? Theme.colors.red : Theme.colors.text
            font.family: Theme.iconFamily
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Scroll wheel volume control
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onWheel: wheel => {
            const delta = wheel.angleDelta.y !== 0
                ? wheel.angleDelta.y : wheel.pixelDelta.y;
            if (delta !== 0) {
                const newVolume = AudioService.volume + (delta > 0 ? 0.05 : -0.05);
                OsdService.suppressVolume();
                AudioService.setVolume(newVolume);
                wheel.accepted = true;
            }
        }

        // Optional: click to open control center
        onClicked: {
            // You could emit a signal here to open the control center
            // For now, just toggle mute
            if (AudioService.output && AudioService.output.audio) {
                AudioService.output.audio.muted = !AudioService.output.audio.muted;
            }
        }
    }

    // Tooltip on hover
    HoverHandler {
        id: hoverHandler
    }

    PanelWindow {
        id: tooltip
        readonly property var hostWindow: root.QsWindow.window
        readonly property point triggerPosition: {
            // Observe layout movement as well as the mapped position.
            const triggerBounds = Qt.rect(root.x, root.y, root.width, root.height);
            const rowPosition = root.parent ? Qt.point(root.parent.x, root.parent.y) : Qt.point(0, 0);
            return hostWindow ? root.mapToItem(hostWindow.contentItem,
                triggerBounds.width / 2, triggerBounds.height) : rowPosition;
        }
        visible: tooltipMotion.active
        screen: hostWindow?.screen ?? null
        anchors { top: true; left: true }
        margins.top: Theme.barHeight + 6
        margins.left: Math.max(8, Math.min(triggerPosition.x - width / 2,
            (screen?.width ?? 1920) - width - 8))
        implicitWidth: tooltipText.implicitWidth + 30
        implicitHeight: tooltipText.implicitHeight + 20 + tooltipMotion.distance
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:tooltip"
        color: "transparent"
        mask: Region {}

        PopupMotion {
            id: tooltipMotion
            opened: hoverHandler.hovered && root.isBluetoothAudio
                && AudioService.output !== null
            attached: false
            distance: 10
        }

        Rectangle {
            x: 3
            width: parent.width - 6
            height: tooltipText.implicitHeight + 20
            y: tooltipMotion.offsetY
            transform: Scale {
                origin.x: (tooltip.width - 6) / 2
                origin.y: 0
                xScale: tooltipMotion.scaleX
                yScale: tooltipMotion.scaleY
            }
            radius: Theme.radius
            color: Theme.colors.mantle
            border.width: 1
            border.color: Theme.colors.surface1

            Text {
                id: tooltipText
                anchors.centerIn: parent
                text: AudioService.output ? AudioService.label(AudioService.output) : ""
                color: Theme.colors.text
                font.family: Theme.textFamily
                font.pixelSize: 11
            }
        }
    }
}
