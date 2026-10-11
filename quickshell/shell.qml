//@ pragma UseQApplication

// Entry point. Wires the per-output bars and shared overlays together. Shared
// state lives in the singletons under components/.
//
// Layout of this configuration:
//   bar/         the top bar and everything that lives in it
//   overlays/    transient panels above the bar (toasts, polkit prompt)
//   background/  the wallpaper video surface, one per output
//   components/  singletons only - no windows live here
//   modules/     pure JS helpers, unit tested in tests/
//   assets/      fonts
//   scripts/     launcher and integrations without a native Quickshell API

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "components"
import "bar"
import "overlays"
import "background"

ShellRoot {
    id: root

    // Public endpoints are shared by every bar. Resolve the pointer output
    // for each request instead of registering a competing handler per bar.
    property var popupRequests: []
    readonly property var iconCatalog: IconThemeCatalog

    function requestPopup(name, argument) {
        popupRequests = popupRequests.concat([{ name: name, argument: argument || "" }]);
        // Rotation lives in IPC metadata rather than a monitor property.
        Hyprland.refreshMonitors();
        if (!cursorPosition.running)
            cursorPosition.running = true;
    }

    function dispatchPopup(point) {
        const request = popupRequests[0];
        popupRequests = popupRequests.slice(1);
        if (!request)
            return;
        const screen = OverlayService.screenAt(point)
            || Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
            || Quickshell.screens[0];
        const bar = bars.instances.find(instance => instance.screen === screen);
        if (bar) {
            if (request.name === "applauncher") bar.toggleLauncher();
            else if (request.name === "clock") bar.toggleClock();
            else if (request.name === "mediaplayer") bar.toggleMediaPlayer();
            else if (request.name === "clipboard") bar.toggleClipboard();
            else if (request.name === "controlcenter") bar.toggleControlCenter();
            else if (request.name === "controlcenter-menu") bar.openControlMenu(request.argument);
        }
    }

    Process {
        id: cursorPosition
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector { id: cursorOutput }
        onExited: function(exitCode) {
            let point = null;
            if (exitCode === 0) {
                try { point = JSON.parse(cursorOutput.text); }
                catch (error) { console.warn("Could not read cursor output:", error); }
            }
            root.dispatchPopup(point);
            if (root.popupRequests.length)
                Qt.callLater(() => { cursorPosition.running = true; });
        }
    }

    IpcHandler {
        target: "applauncher"
        function toggle(): void { root.requestPopup("applauncher"); }
    }
    IpcHandler {
        target: "clock"
        function toggle(): void { root.requestPopup("clock"); }
    }
    IpcHandler {
        target: "mediaplayer"
        function toggle(): void { root.requestPopup("mediaplayer"); }
    }
    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.requestPopup("clipboard"); }
    }
    IpcHandler {
        target: "controlcenter"
        function toggle(): void { root.requestPopup("controlcenter"); }
        function close(): void {
            root.popupRequests = root.popupRequests.filter(request => !request.name.startsWith("controlcenter"));
            for (const bar of bars.instances)
                bar.closeControlCenter();
        }
        function menu(name: string): void {
            if (["network", "bluetooth", "wallpaper", "nightLight"].indexOf(name) >= 0)
                root.requestPopup("controlcenter-menu", name);
        }
    }
    IpcHandler {
        target: "icons"
        function list(): string { return root.iconCatalog.list(); }
        function current(): string { return IconThemeService.themeName; }
    }

    // Created first so the wallpaper is on screen before the bar draws over it.
    WallpaperSurface {}
    Variants {
        id: bars
        model: Quickshell.screens
        Bar {
            required property var modelData
            screen: modelData
        }
    }
    PolkitDialog {}
    NotificationToast { id: fullscreenNotification }
    NowPlayingToast { id: fullscreenNowPlaying }
    Osd { id: fullscreenOsd }
    MediaTransfer {}

    IpcHandler {
        target: "fullscreenpreview"
        function snapshot(): string {
            return JSON.stringify({ osd: fullscreenOsd.margins.top,
                notifications: fullscreenNotification.margins.top,
                nowPlaying: fullscreenNowPlaying.margins.top });
        }
        function nowplaying(): void {
            NowPlayingService.showToast();
        }
        function notification(): void {
            const preview = { id: "fullscreen-preview", summary: "Fullscreen notification",
                body: "Attached to the top edge when the bar is hidden.", appIcon: "dialog-information", image: "" };
            NotificationManager.toastQueue = [preview].concat(
                NotificationManager.toastQueue.filter(t => t.id !== preview.id));
        }
        function clear(): void {
            NowPlayingService.dismissToast();
            fullscreenOsd.showing = false;
            NotificationManager.removeToast("fullscreen-preview");
        }
    }
}
