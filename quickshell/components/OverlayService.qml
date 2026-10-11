pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../modules/screens.js" as Screens

// All attached overlays follow the bar's visibility on their own output.
QtObject {
    function screenAt(point) {
        return Screens.screenAt(point, Quickshell.screens, Hyprland.monitors.values);
    }

    function topMargin(screen) {
        const monitor = screen ? Hyprland.monitorFor(screen) : null;
        const workspace = monitor?.activeWorkspace;
        if (!workspace?.hasFullscreen)
            return Theme.barHeight;

        // Hyprland also marks maximized workspaces as having fullscreen.
        // Only internal mode 2 covers the bar; mode 1 keeps it visible.
        for (const window of workspace.toplevels.values) {
            if ((Number(window.lastIpcObject?.fullscreen) & 2) !== 0)
                return 0;
        }
        return Theme.barHeight;
    }

    // Fullscreen has no dedicated HyprlandToplevel property. Refresh its IPC
    // metadata when the compositor changes it, rather than polling for it.
    property Connections fullscreenEvents: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen")
                Hyprland.refreshToplevels();
        }
    }

    Component.onCompleted: Hyprland.refreshToplevels()
}
