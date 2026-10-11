pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Shared Material palette generated from the current wallpaper. Watch the
// cache so manual regeneration and toolkit updates also reach the bar.
QtObject {
    id: theme
    property bool darkMode: true
    property var palette: ({})

    readonly property string paletteFile: Quickshell.env("HOME")
        + "/.cache/avethy/palette.ini"

    function parsePalette() {
        const values = {};
        const lines = (paletteStore.text() || "").split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const eq = lines[i].indexOf("=");
            if (eq > 0)
                values[lines[i].slice(0, eq).trim()] = lines[i].slice(eq + 1).trim();
        }
        palette = values;
    }

    function reloadPalette() {
        paletteStore.reload();
    }

    function colorFor(role, fallbackDark, fallbackLight) {
        const key = (darkMode ? "dark." : "light.") + role;
        return palette[key] || (darkMode ? fallbackDark : fallbackLight);
    }

    property FileView paletteStore: FileView {
        path: theme.paletteFile
        watchChanges: true
        printErrors: false
        blockLoading: true
        preload: true
        onLoaded: theme.parsePalette()
        onFileChanged: reload()
    }
    // Direct `qs` launches receive the same desktop configuration. The normal
    // launcher applies it first so desktop entries inherit Avethy immediately.
    property Process startupTheme: Process {
        command: ["python3", Quickshell.shellPath("scripts/material-palette.py"), "--startup"]
        onExited: function(exitCode) {
            if (exitCode === 0)
                theme.reloadPalette();
            else
                console.error("Avethy: desktop theme startup failed (" + exitCode + ")");
        }
    }
    Component.onCompleted: {
        if (Quickshell.env("AVETHY_THEME_READY") !== "1")
            startupTheme.running = true;
    }
    readonly property FontLoader iconFont: FontLoader {
        source: Qt.resolvedUrl("../assets/icons/MaterialIconsRound-Regular.otf")
    }
    readonly property string iconFamily: iconFont.name
    // SF Pro Text is installed system-wide from /usr/share/fonts/SF-Fonts
    // (mounted at /run/host/fonts for the shell runtime).
    readonly property string textFamily: "SF Pro Text"

    readonly property QtObject colors: QtObject {
        readonly property color base: theme.colorFor("background", "#141218", "#fffbfe")
        readonly property color mantle: theme.colorFor("surface_container_lowest", "#0f0d13", "#ffffff")
        readonly property color crust: theme.colorFor("on_primary", "#381e72", "#ffffff")
        readonly property color surface0: theme.colorFor("surface_container", "#211f26", "#f3edf7")
        readonly property color surface1: theme.colorFor("surface_container_high", "#2b2930", "#ece6f0")
        readonly property color surface2: theme.colorFor("surface_container_highest", "#36343b", "#e6e0e9")
        readonly property color text: theme.colorFor("on_surface", "#e6e0e9", "#1d1b20")
        readonly property color textDim: theme.colorFor("on_surface_variant", "#cac4d0", "#49454f")
        readonly property color blue: theme.colorFor("secondary", "#ccc2dc", "#625b71")
        readonly property color green: theme.colorFor("success", "#75db91", "#146c2e")
        readonly property color mauve: theme.colorFor("primary", "#d0bcff", "#6750a4")
        readonly property color red: theme.colorFor("error", "#ffb4ab", "#ba1a1a")
        readonly property color yellow: theme.colorFor("warning", "#e9c349", "#745b00")
        readonly property color outline: theme.colorFor("outline", "#938f99", "#79747e")
    }

    // Shared tint for surfaces that use the bar's compositor blur rule.
    readonly property color barBackground: Qt.rgba(colors.base.r, colors.base.g,
                                                   colors.base.b, 0.62)

    // Inner cards are more opaque than the popup glass for readable controls.
    readonly property color popupSurface0: Qt.rgba(colors.surface0.r, colors.surface0.g,
                                                    colors.surface0.b, 0.82)
    readonly property color popupSurface1: Qt.rgba(colors.surface1.r, colors.surface1.g,
                                                    colors.surface1.b, 0.88)
    readonly property color popupSurface2: Qt.rgba(colors.surface2.r, colors.surface2.g,
                                                    colors.surface2.b, 0.94)

    readonly property int radius: 12
    readonly property int barHeight: 42
    readonly property int spacing: 8

    // Gap between a bar button and the popup it opens.
    readonly property int popupGap: 8
    // Top offset for overlay panels that need to clear the bar.
    readonly property int overlayTop: barHeight + 28
}
