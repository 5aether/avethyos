pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// User settings file: ~/.config/quickshell/config.ini
//
// The shell writes it, and it is a plain INI file, so you can also edit it by
// hand while quickshell is not running:
//
//   [wallpaper]
//   path = file:///absolute/path/to/wallpaper.mp4
//   folder = ~/Videos/Wallpapers
//   fillMode = cover
//   enabled = true
//
//   [notifications]
//   maxVisibleToasts = 4
//   toastDurationMs = 5200
//   doNotDisturb = false
//
//   [display]
//   nightLightEnabled = false
//   nightLightTemperature = 4000
//
// Any missing key keeps its default below, and any unparsable value is ignored.
QtObject {
    id: root

    readonly property string file: Quickshell.env("HOME") + "/.config/quickshell/config.ini"

    // Wallpaper
    property string wallpaperPath: ""
    property string wallpaperFolder: "~/Videos/Wallpapers"
    property string wallpaperFillMode: "cover"
    property bool wallpaperEnabled: true

    // Notifications
    property int maxVisibleToasts: 4
    property int toastDurationMs: 5200
    property bool doNotDisturb: false

    // Display
    property bool nightLightEnabled: false
    property int nightLightTemperature: 4000

    property FileView store: FileView {
        path: root.file
        printErrors: false
        watchChanges: true
        blockLoading: true
        preload: true

        onLoaded: root.parse()
        onFileChanged: reload()
    }

    // Minimal INI reader for flat "key = value" lines with [section] headers.
    function parse() {
        const lines = (store.text() || "").split("\n");
        let section = "";
        const found = {};
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim();
            if (!line.length || line.startsWith(";") || line.startsWith("#"))
                continue;
            if (line.startsWith("[") && line.endsWith("]")) {
                section = line.slice(1, -1).trim();
                continue;
            }
            const eq = line.indexOf("=");
            if (eq < 0)
                continue;
            const key = line.slice(0, eq).trim();
            if (key)
                found[section + "." + key] = line.slice(eq + 1).trim();
        }
        root.apply(found);
    }

    // Accepts the usual truthy and falsy spellings so a hand-edited file does
    // not silently read "no" as true.
    function toBool(value, fallback) {
        const text = String(value).trim().toLowerCase();
        if (text === "true" || text === "yes" || text === "1" || text === "on")
            return true;
        if (text === "false" || text === "no" || text === "0" || text === "off")
            return false;
        return fallback;
    }

    function apply(values) {
        const path = values["wallpaper.path"];
        if (path !== undefined)
            wallpaperPath = path;

        const folder = values["wallpaper.folder"];
        if (folder !== undefined)
            wallpaperFolder = folder || "~/Videos/Wallpapers";

        const mode = values["wallpaper.fillMode"];
        if (mode !== undefined)
            wallpaperFillMode = (mode === "fit" || mode === "stretch") ? mode : "cover";

        const on = values["wallpaper.enabled"];
        if (on !== undefined)
            wallpaperEnabled = toBool(on, wallpaperEnabled);

        const toasts = parseInt(values["notifications.maxVisibleToasts"], 10);
        if (!isNaN(toasts))
            maxVisibleToasts = Math.max(1, Math.min(10, toasts));

        const duration = parseInt(values["notifications.toastDurationMs"], 10);
        if (!isNaN(duration))
            toastDurationMs = Math.max(1500, duration);

        const dnd = values["notifications.doNotDisturb"];
        if (dnd !== undefined)
            doNotDisturb = toBool(dnd, doNotDisturb);

        const nightLight = values["display.nightLightEnabled"];
        if (nightLight !== undefined)
            nightLightEnabled = toBool(nightLight, nightLightEnabled);

        const temperature = parseInt(values["display.nightLightTemperature"], 10);
        if (!isNaN(temperature))
            nightLightTemperature = Math.max(1000, Math.min(6500, temperature));
    }

    // Serializes the current values back into the format parse() reads.
    function save() {
        store.setText("[wallpaper]\n"
            + "path = " + wallpaperPath + "\n"
            + "folder = " + wallpaperFolder + "\n"
            + "fillMode = " + wallpaperFillMode + "\n"
            + "enabled = " + (wallpaperEnabled ? "true" : "false") + "\n"
            + "\n[notifications]\n"
            + "maxVisibleToasts = " + maxVisibleToasts + "\n"
            + "toastDurationMs = " + toastDurationMs + "\n"
            + "doNotDisturb = " + (doNotDisturb ? "true" : "false") + "\n"
            + "\n[display]\n"
            + "nightLightEnabled = " + (nightLightEnabled ? "true" : "false") + "\n"
            + "nightLightTemperature = " + nightLightTemperature + "\n");
    }
    function setWallpaper(path, fillMode, enabled) {
        if (fillMode !== undefined && fillMode !== null)
            wallpaperFillMode = fillMode;
        if (enabled !== undefined)
            wallpaperEnabled = enabled;
        if (path !== undefined && path !== null)
            wallpaperPath = path;
        save();
    }

    function setDoNotDisturb(value) {
        doNotDisturb = value;
        save();
    }

    function setNightLight(value) {
        nightLightEnabled = value;
        save();
    }

    function setNightLightTemperature(value) {
        nightLightTemperature = Math.max(1000, Math.min(6500, Math.round(value)));
        save();
    }
}
