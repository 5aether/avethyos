import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../components"
import "../widgets"

// Volume/brightness feedback attached below the bar at the top right.
// The window never takes focus or reserves compositor space.
PanelWindow {
    id: root

    property string kind: "volume"
    property int value: 0
    property bool muted: false
    property bool showing: false
    property bool ready: false
    property int lastBrightness: -1
    readonly property int blendHeight: 36
    readonly property bool shouldShow: showing

    function syncWindows() {
        if (popupMotion.active) {
            blurBackdrop.visible = true;
            root.visible = true;
        } else {
            root.visible = false;
            blurBackdrop.visible = false;
        }
    }

    PopupMotion {
        id: popupMotion
        opened: root.shouldShow
        distance: card.height
        onActiveChanged: root.syncWindows()
    }

    readonly property color accent: kind === "brightness"
        ? Theme.colors.yellow : Theme.colors.blue
    readonly property string icon: kind === "brightness" ? "brightness_6"
        : muted || value <= 0 ? "volume_off"
        : value < 50 ? "volume_down" : "volume_up"

    function showVolume() {
        kind = "volume";
        value = Math.round(AudioService.volume * 100);
        muted = AudioService.muted;
        showing = true;
        dismissTimer.restart();
    }

    function showBrightness(level) {
        const parsed = Math.max(0, Math.min(100, Math.round(Number(level))));
        if (!isFinite(parsed))
            return;
        kind = "brightness";
        value = parsed;
        muted = false;
        showing = true;
        dismissTimer.restart();
    }

    visible: false
    onVisibleChanged: OsdService.overlayVisible = visible
    Component.onDestruction: OsdService.overlayVisible = false
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:osd"
    focusable: false
    color: "transparent"

    anchors { top: true; right: true }
    margins.top: OverlayService.topMargin(root.screen)
    implicitWidth: card.width
    implicitHeight: card.height + 8

    Component.onCompleted: {
        syncWindows();
        Qt.callLater(function() { root.ready = true; });
    }

    Connections {
        target: AudioService
        function onVolumeChanged() {
            if (root.ready && OsdService.volumeAllowed()) root.showVolume();
        }
        function onMutedChanged() {
            if (root.ready && OsdService.volumeAllowed()) root.showVolume();
        }
    }

    IpcHandler {
        target: "osd"
        function volume(): void { root.showVolume(); }
        function brightness(level: int): void {
            root.lastBrightness = level;
            root.showBrightness(level);
        }
    }

    Timer {
        id: dismissTimer
        interval: 1400
        onTriggered: {
            root.showing = false;
        }
    }

    PanelWindow {
        id: blurBackdrop
        visible: false
        screen: root.screen
        anchors { top: true; right: true }
        margins.top: root.margins.top
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        // Dedicated namespace keeps Hyprland from animating the glass join.
        WlrLayershell.namespace: "quickshell:popup-backdrop"
        focusable: false
        color: "transparent"
        mask: Region {}
        implicitWidth: root.width
        implicitHeight: root.height

        AttachedPanel {
            width: card.width
            height: card.height
            flowProgress: popupMotion.progress
            flowStrength: 0.075
            color: Theme.barBackground
            cornerRadius: card.cornerRadius
            transform: [
                Translate { y: popupMotion.offsetY },
                Scale {
                    origin.x: card.width
                    origin.y: 0
                    xScale: popupMotion.scaleX
                    yScale: popupMotion.scaleY
                }
            ]
        }
    }

    AttachedPanel {
        id: card
        color: "transparent"
        flowProgress: popupMotion.progress
        flowStrength: 0.075
        anchors.right: parent.right
        anchors.top: parent.top
        width: 280 + cornerRadius
        height: 56 + cornerRadius
        transform: [
            Translate { y: popupMotion.offsetY },
            Scale {
                origin.x: card.width
                origin.y: 0
                xScale: popupMotion.scaleX
                yScale: popupMotion.scaleY
            }
        ]

        ClippingRectangle {
            id: panel
            anchors.right: parent.right
            anchors.top: parent.top
            width: card.width - card.cornerRadius
            height: card.bodyBottom
            topLeftRadius: Theme.radius
            bottomLeftRadius: Theme.radius
            topRightRadius: Theme.radius
            bottomRightRadius: Theme.radius
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                spacing: 12

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.icon
                    color: root.accent
                    font.family: Theme.iconFamily
                    font.pixelSize: 23
                }

                Item {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: Theme.colors.surface0
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * (root.muted ? 0 : root.value / 100)
                        radius: Theme.radius
                        color: root.accent

                        Behavior on width {
                            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignRight
                    text: root.value + "%"
                    color: Theme.colors.text
                    font.family: Theme.textFamily
                    font.pixelSize: 11
                    font.bold: true
                }
            }
        }
    }
}
