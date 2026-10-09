//@ pragma UseQApplication

// Entry point. Wires the four windows of the shell together; every piece of
// shared state lives in the singletons under components/.
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
import "components"
import "bar"
import "overlays"
import "background"

ShellRoot {
    // Keep the public endpoint directly under ShellRoot so it is registered
    // as part of initial configuration construction.
    IpcHandler {
        target: "applauncher"
        function toggle(): void { bar.toggleLauncher(); }
    }

    // Created first so the wallpaper is on screen before the bar draws over it.
    WallpaperSurface {}
    Bar { id: bar }
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
