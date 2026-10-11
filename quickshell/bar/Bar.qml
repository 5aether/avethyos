import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../components"

PanelWindow {
    id: barWindow

    // The bar and attached glass share one native surface so live blur reads
    // the windows once, including at their join.
    property alias glassHost: glassHost

    Component.onCompleted: BarGlassService.registerBar(barWindow)
    Component.onDestruction: BarGlassService.unregisterBar(barWindow)

    function toggleLauncher(): void {
        appMenu.togglePopup();
    }

    function toggleClock(): void { clock.togglePopup(); }
    function toggleMediaPlayer(): void { mediaPlayer.togglePopup(); }
    function toggleClipboard(): void { clipboard.togglePopup(); }
    function toggleControlCenter(): void { controlCenter.togglePopup(); }
    function closeControlCenter(): void { controlCenter.popupOpen = false; }
    function openControlMenu(name): void {
        if (!controlCenter.popupOpen)
            controlCenter.togglePopup();
        controlCenter.openMenu(name);
    }

    anchors {
        top: true
        left: true
        right: true
    }

    // Keep the native surface and swapchain fixed across popup transitions.
    // Resizing it at either endpoint can flash the compositor's blur buffer.
    // Only the painted shapes grow; reservation and input stay bar-height.
    implicitHeight: screen?.height ?? 1080
    exclusiveZone: Theme.barHeight
    color: "transparent"
    mask: Region { item: barContent }
    // Identified for hyprctl layers / layerrule matching (blur + blur_popups).
    WlrLayershell.namespace: "quickshell:bar"

    Rectangle {
        width: parent.width
        height: Theme.barHeight
        color: Theme.barBackground
    }

    Item {
        id: glassHost
        y: Theme.barHeight
        width: parent.width
        height: Math.max(0, parent.height - y)
        clip: true
    }

    Item {
        id: barContent
        width: parent.width
        height: Theme.barHeight

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
            id: mediaPlayer
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 8
        }
        BluetoothAudio {}
        Clipboard { id: clipboard }
        ControlCenter { id: controlCenter }
    }
    }
}
