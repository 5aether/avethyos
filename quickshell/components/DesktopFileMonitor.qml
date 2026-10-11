pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Keep launcher entries and icon sources current as installers change files.
QtObject {
    id: root
    signal applicationsChanged()
    signal iconsChanged()

    property Process watcher: Process {
        command: ["python3", Quickshell.shellPath("scripts/desktop-watch.py")]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const change = JSON.parse(data);
                    if (change.applications) root.applicationsChanged();
                    if (change.icons) root.iconsChanged();
                } catch (error) {
                    console.warn("Could not read desktop file changes:", error);
                }
            }
        }
        onExited: function(exitCode) {
            console.warn("Desktop file monitor exited:", exitCode);
            retry.restart();
        }
    }

    property Timer retry: Timer {
        interval: 1500
        onTriggered: watcher.running = true
    }
}
