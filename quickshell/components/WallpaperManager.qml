pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string requestedPath: ""
    property bool enabled: true
    property int fillMode: Image.PreserveAspectCrop
    property string error: ""
    property string pendingPaletteSource: ""
    property bool paletteQueued: false

    readonly property bool shouldRun: enabled && requestedPath.length > 0

    // Reads one setting from Config and applies it. Only the key that actually
    // changed is touched, so an unrelated edit cannot clear a playback error
    // reported moments earlier.
    function applyPath() {
        requestedPath = String(Config.wallpaperPath || "");
    }

    function applyFillMode() {
        fillMode = Config.wallpaperFillMode === "fit" ? Image.PreserveAspectFit
                 : Config.wallpaperFillMode === "stretch" ? Image.Stretch
                 : Image.PreserveAspectCrop;
    }

    function applyEnabled() {
        enabled = Config.wallpaperEnabled;
    }

    function applyConfig() {
        applyEnabled();
        applyFillMode();
        applyPath();
        error = "";
    }

    function setPath(value) {
        const text = String(value || "").trim();
        // Already a URL (file://, http://, ...): use as is. A bare path gets a
        // file:// prefix so QtMultimedia resolves it correctly.
        const url = !text.length ? ""
                  : /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(text) ? text
                  : "file://" + (text.startsWith("/") ? "" : "/") + text;
        const changed = url !== requestedPath;
        error = "";
        Config.setWallpaper(url, undefined, enabled);
        if (changed)
            generatePalette(url);
    }

    // Palette work is event-driven: selecting a wallpaper launches one helper
    // and then it exits. If selections arrive quickly, discard intermediate
    // work and generate only for the most recent path after the active run.
    function generatePalette(source) {
        const value = String(source || "");
        if (paletteGenerator.running) {
            pendingPaletteSource = value;
            paletteQueued = true;
            return;
        }
        paletteGenerator.command = [
            "python3",
            Quickshell.shellPath("scripts/material-palette.py"),
            "--source",
            value,
            "--mode",
            Theme.darkMode ? "dark" : "light"
        ];
        paletteGenerator.running = true;
    }

    property Process paletteGenerator: Process {
        onExited: function(exitCode) {
            if (exitCode === 0)
                Theme.reloadPalette();
            if (root.paletteQueued) {
                const source = root.pendingPaletteSource;
                root.paletteQueued = false;
                root.pendingPaletteSource = "";
                Qt.callLater(function() { root.generatePalette(source); });
            }
        }
    }

    function setFillMode(mode) {
        const name = mode === Image.PreserveAspectFit ? "fit"
                   : mode === Image.Stretch ? "stretch" : "cover";
        Config.setWallpaper(undefined, name, enabled);
    }

    function setEnabled(value) {
        Config.setWallpaper(undefined, undefined, value);
    }

    function reportError(message) {
        error = String(message || "QtMultimedia playback failed");
    }

    Component.onCompleted: applyConfig()

    // One handler per key, so each change does the minimum necessary work.
    property Connections configConnections: Connections {
        target: Config
        function onWallpaperPathChanged() { root.applyPath(); }
        function onWallpaperFillModeChanged() { root.applyFillMode(); }
        function onWallpaperEnabledChanged() { root.applyEnabled(); }
    }
}
