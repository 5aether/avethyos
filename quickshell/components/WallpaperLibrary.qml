pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// One library shared by the collapsed wallpaper tile and the expanded menu.
// Folder discovery stays fast; a separate process streams cached still frames.
QtObject {
    id: root
    property bool active: false
    property string folder: ""
    property string currentDirectory: ""
    property string relativeDirectory: "."
    property string parentDirectory: ""
    property var entries: []
    property var thumbnailSources: ({})
    property string error: ""
    property string currentThumbnail: ""
    property string currentUrl: ""
    readonly property bool loading: scanInFlight || refreshPending
    readonly property bool thumbnailBusy: thumbnailInFlight
    readonly property bool atRoot: !parentDirectory.length

    property string directoryRequest: ""
    property int revision: 0
    property bool refreshPending: false
    property bool thumbnailsPending: false
    property bool previewPending: false
    property bool scanInFlight: false
    property bool thumbnailInFlight: false
    property bool previewInFlight: false

    function refresh() {
        ++revision;
        error = "";
        thumbnailsPending = false;
        thumbnailer.running = false;
        refreshPending = true;
        if (!scanInFlight)
            startScan();
    }

    function startScan() {
        if (scanInFlight || !refreshPending)
            return;
        refreshPending = false;
        scanInFlight = true;
        scanner.revision = revision;
        scanner.command = ["python3", Quickshell.shellPath("scripts/wallpaper-library.py"),
            "scan", "--folder", Config.wallpaperFolder, "--directory", directoryRequest];
        scanner.running = true;
    }

    function browse(directory) {
        directoryRequest = String(directory || "");
        entries = [];
        refresh();
    }

    function up() {
        if (parentDirectory.length)
            browse(parentDirectory);
    }

    function home() { browse(""); }

    function beginThumbnails() {
        if (!active || error.length)
            return;
        thumbnailsPending = true;
        thumbnailStarter.restart();
    }

    function receiveThumbnail(line) {
        if (thumbnailer.revision !== revision)
            return;
        try {
            const result = JSON.parse(line);
            if (!result.url || !result.thumbnail)
                return;
            const updated = Object.assign({}, thumbnailSources);
            updated[result.url] = result.thumbnail;
            thumbnailSources = updated;
            if (isCurrent(result.url))
                currentThumbnail = result.thumbnail;
        } catch (failure) {
            console.warn("Wallpaper thumbnail:", failure);
        }
    }

    // Keep previews separate from the grid's model. Replacing a JS-array
    // model per thumbnail would recreate every delegate and disturb scrolling.
    function thumbnailFor(url, fallback) {
        return thumbnailSources[String(url || "")] || String(fallback || "");
    }

    function isCurrent(url) {
        return String(url || "") === currentUrl || String(url || "") === Config.wallpaperPath;
    }

    function refreshCurrentPreview() {
        currentUrl = Config.wallpaperPath;
        currentThumbnail = "";
        for (let i = 0; i < entries.length; ++i) {
            if (isCurrent(entries[i].url) && thumbnailFor(entries[i].url, entries[i].thumbnail)) {
                currentThumbnail = thumbnailFor(entries[i].url, entries[i].thumbnail);
                break;
            }
        }
        previewPending = true;
        if (!previewInFlight)
            startCurrentPreview();
    }

    function startCurrentPreview() {
        if (previewInFlight || !previewPending)
            return;
        previewPending = false;
        const source = String(Config.wallpaperPath || "");
        if (!source.length)
            return;
        previewInFlight = true;
        currentPreview.sourcePath = source;
        currentPreview.command = ["python3", Quickshell.shellPath("scripts/wallpaper-library.py"),
            "preview", "--source", source];
        currentPreview.running = true;
    }

    onActiveChanged: {
        if (active)
            refresh();
        else {
            ++revision;
            refreshPending = false;
            scanner.running = false;
            thumbnailsPending = false;
            thumbnailer.running = false;
            thumbnailStarter.stop();
        }
    }

    Component.onCompleted: refreshCurrentPreview()

    property Connections configChanges: Connections {
        target: Config
        function onWallpaperPathChanged() { root.refreshCurrentPreview(); }
        function onWallpaperFolderChanged() {
            ++root.revision;
            root.directoryRequest = "";
            root.currentDirectory = "";
            root.parentDirectory = "";
            root.relativeDirectory = ".";
            root.folder = "";
            root.entries = [];
            root.thumbnailSources = ({});
            if (root.active)
                root.refresh();
        }
    }

    property Process scanner: Process {
        property int revision: -1
        stdout: StdioCollector {
            onStreamFinished: {
                if (scanner.revision !== root.revision)
                    return;
                try {
                    const result = JSON.parse(text);
                    root.error = result.error || "";
                    root.entries = result.entries || [];
                    root.thumbnailSources = ({});
                    root.folder = result.folder || "";
                    root.currentDirectory = result.directory || "";
                    root.relativeDirectory = result.relativeDirectory || ".";
                    root.parentDirectory = result.parent || "";
                    root.beginThumbnails();
                } catch (failure) {
                    root.error = "Could not read the wallpaper folder";
                    root.entries = [];
                }
            }
        }
        onExited: function(exitCode) {
            root.scanInFlight = false;
            if (exitCode !== 0 && !root.error.length && revision === root.revision)
                root.error = "Could not read the wallpaper folder";
            if (root.refreshPending)
                Qt.callLater(root.startScan);
        }
    }

    property Timer thumbnailStarter: Timer {
        interval: 50
        onTriggered: {
            if (!root.active || !root.thumbnailsPending)
                return;
            if (root.thumbnailInFlight) {
                restart();
                return;
            }
            root.thumbnailsPending = false;
            root.thumbnailInFlight = true;
            thumbnailer.revision = root.revision;
            thumbnailer.command = ["python3", Quickshell.shellPath("scripts/wallpaper-library.py"),
                "thumbnails", "--folder", Config.wallpaperFolder, "--directory", root.currentDirectory];
            thumbnailer.running = true;
        }
    }

    property Process thumbnailer: Process {
        property int revision: -1
        stdout: SplitParser { onRead: line => root.receiveThumbnail(line) }
        onExited: root.thumbnailInFlight = false
    }

    property Process currentPreview: Process {
        property string sourcePath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (currentPreview.sourcePath !== Config.wallpaperPath)
                    return;
                try {
                    const result = JSON.parse(text);
                    root.currentThumbnail = result.thumbnail || "";
                    root.currentUrl = result.url || Config.wallpaperPath;
                } catch (failure) {
                    root.currentThumbnail = "";
                }
            }
        }
        onExited: {
            root.previewInFlight = false;
            if (root.previewPending)
                Qt.callLater(root.startCurrentPreview);
        }
    }
}
