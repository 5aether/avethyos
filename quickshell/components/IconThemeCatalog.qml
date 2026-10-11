pragma Singleton

import QtQuick
import QtQml.Models
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

// Directory models watch for installed/removed themes. Read only the small
// index.theme files when explicitly asked to list packs, never the icon files.
QtObject {
    id: root
    property var searchRoots: []
    property bool refreshPending: false

    function refreshRoots() {
        if (rootsQuery.running)
            refreshPending = true;
        else
            rootsRefresh.restart();
    }

    property Timer rootsRefresh: Timer {
        interval: 80
        onTriggered: rootsQuery.running = true
    }

    property Process rootsQuery: Process {
        command: ["python3", Quickshell.shellPath("scripts/icon-theme.py"), "--watch-roots"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const paths = JSON.parse(text);
                    if (JSON.stringify(paths) !== JSON.stringify(root.searchRoots))
                        root.searchRoots = paths;
                }
                catch (error) { console.warn("Could not read icon search paths:", error); }
            }
        }
        onExited: {
            if (root.refreshPending) {
                root.refreshPending = false;
                rootsRefresh.restart();
            }
        }
    }

    property Instantiator directories: Instantiator {
        model: root.searchRoots
        delegate: QtObject {
            id: entry
            required property var modelData
            property FolderListModel themes: FolderListModel {
                folder: "file://" + entry.modelData.path
                showFiles: false
                showDirs: true
                showDotAndDotDot: false
                showOnlyReadable: true
            }
            property FolderListModel parentWatch: FolderListModel {
                folder: "file://" + entry.modelData.parent
                showFiles: false
                showDotAndDotDot: false
                onCountChanged: root.refreshRoots()
                onStatusChanged: root.refreshRoots()
            }
        }
    }

    property FileView indexFile: FileView {
        printErrors: false
        blockAllReads: true
    }

    function list() {
        if (!searchRoots.length)
            return "Icon search paths are still loading. Run the command again in a moment.";
        const paths = new Map();
        const themes = new Set();
        for (let i = 0; i < directories.count; ++i) {
            const entry = directories.objectAt(i);
            const directory = entry ? entry.themes : null;
            if (!directory || directory.status !== FolderListModel.Ready)
                continue;
            for (let j = 0; j < directory.count; ++j) {
                const name = String(directory.get(j, "fileName"));
                const path = String(directory.get(j, "filePath"));
                if (!path.startsWith(entry.modelData.path + "/"))
                    continue;
                if (!paths.has(name))
                    paths.set(name, []);
                paths.get(name).push(path);
                indexFile.path = path + "/index.theme";
                indexFile.reload();
                if (/^\s*\[Icon Theme\]\s*$/m.test(indexFile.text()))
                    themes.add(name);
            }
        }
        const names = Array.from(themes).sort((a, b) => {
            const lowerA = a.toLowerCase();
            const lowerB = b.toLowerCase();
            return lowerA < lowerB ? -1 : lowerA > lowerB ? 1 : a < b ? -1 : a > b ? 1 : 0;
        });
        if (!names.length)
            return "No installed icon packs found.";
        const lines = ["Exact names for [appearance] icon-pack:"];
        for (const name of names) {
            lines.push(name);
            for (const path of paths.get(name))
                lines.push("  " + path);
        }
        return lines.join("\n");
    }
}
