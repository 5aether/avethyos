import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../components"

PanelWindow {
    id: barWindow

    function toggleLauncher(): void {
        appMenu.togglePopup();
    }

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Theme.barHeight
    // Translucent so the compositor blur shows through; the layer rule for
    // this namespace lives in hyprland.lua.
    color: Theme.barBackground
    // Identified for hyprctl layers / layerrule matching (blur + blur_popups).
    WlrLayershell.namespace: "quickshell:bar"

    // Side groups stay pinned to the edges independently of the center group.
    RowLayout {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing

        AppMenu {
            id: appMenu
            launcherScreen: barWindow.screen
            availableWidth: barWindow.width
            availableHeight: barWindow.screen ? barWindow.screen.height : 1080
        }
        Workspaces {}
    }

    Clock {
        id: clock
        anchors.centerIn: parent
    }

    RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        MediaPlayer {
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 8
        }
        BluetoothAudio {}
        Clipboard {}
        ControlCenter {}
    }
}
