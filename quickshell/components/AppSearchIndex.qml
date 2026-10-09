pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var entries: ({})
    property bool refreshPending: false

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

    property Process scanner: Process {
        command: ["python3", Quickshell.shellPath("scripts/desktop-search.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.entries = JSON.parse(text);
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
