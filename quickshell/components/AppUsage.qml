pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Persistent launch counts for applications started through AppMenu.
QtObject {
    id: root

    readonly property string dir: Config.stateDir
    readonly property string file: dir + "/app-usage.json"
    property var counts: ({})
    property int revision: 0

    function record(key) {
        if (!key)
            return;
        const next = Object.assign({}, root.counts);
        next[String(key)] = (Number(next[String(key)]) || 0) + 1;
        root.counts = next;
        root.revision++;
        store.setText(JSON.stringify(next, null, 2) + "\n");
    }

    property Process ensureDir: Process {
        command: ["mkdir", "-p", root.dir]
        running: true
    }

    property FileView store: FileView {
        path: root.file
        printErrors: false
        watchChanges: false
        blockLoading: true
        preload: true

        onLoaded: {
            try {
                const parsed = JSON.parse(store.text() || "{}");
                root.counts = parsed && typeof parsed === "object" ? parsed : {};
            } catch (err) {
                root.counts = {};
            }
            root.revision++;
        }
    }
}
