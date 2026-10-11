pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var entries: ({})
    property var catalog: []
    property string entriesSnapshot: ""
    property string catalogSnapshot: ""
    property bool refreshPending: false

    // File snapshots remain authoritative when Quickshell's native directory
    // watcher missed a newly created root or a replaced Flatpak symlink.
    readonly property var applications: catalog.map(data => {
        const app = Object.assign({}, data);
        app.execute = function() {
            const native = DesktopEntries.byId(data.id);
            if (native && native.execString === data.execString
                    && native.workingDirectory === data.workingDirectory && !data.runInTerminal
                    && !/%[ick]/.test(data.execString))
                native.execute();
            else
                Quickshell.execDetached(["gio", "launch", data.desktopFile]);
        };
        app.actions = data.actions.map(actionData => {
            const action = Object.assign({}, actionData);
            action.execute = function() {
                const native = DesktopEntries.byId(data.id);
                const nativeAction = native ? native.actions.find(item => item.id === actionData.id) : null;
                if (nativeAction && nativeAction.execString === actionData.execString
                        && native.workingDirectory === data.workingDirectory && !/%[ick]/.test(actionData.execString))
                    nativeAction.execute();
                else
                    Quickshell.execDetached({ command: actionData.command, workingDirectory: data.workingDirectory });
            };
            return action;
        });
        return app;
    })

    function refresh() {
        if (scanner.running) {
            refreshPending = true;
            return;
        }
        refreshPending = false;
        scanner.running = true;
    }

    Component.onCompleted: refresh()

    property Connections desktopChanges: Connections {
        target: DesktopEntries
        function onApplicationsChanged() { root.refresh(); }
    }

    property Connections installedFiles: Connections {
        target: DesktopFileMonitor
        function onApplicationsChanged() { root.refresh(); }
    }

    property Process scanner: Process {
        command: ["python3", Quickshell.shellPath("scripts/desktop-search.py"), "--snapshot"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const snapshot = JSON.parse(text);
                    if (!snapshot.entries || Array.isArray(snapshot.entries)
                            || typeof snapshot.entries !== "object" || !Array.isArray(snapshot.applications))
                        throw new Error("Invalid desktop snapshot");
                    const entries = JSON.stringify(snapshot.entries);
                    const catalog = JSON.stringify(snapshot.applications);
                    if (entries !== root.entriesSnapshot) {
                        root.entriesSnapshot = entries;
                        root.entries = snapshot.entries;
                    }
                    if (catalog !== root.catalogSnapshot) {
                        root.catalogSnapshot = catalog;
                        root.catalog = snapshot.applications;
                    }
                } catch (error) {
                    console.warn("Could not read desktop search index:", error);
                }
            }
        }
        onExited: {
            if (root.refreshPending)
                Qt.callLater(root.refresh);
        }
    }
}
