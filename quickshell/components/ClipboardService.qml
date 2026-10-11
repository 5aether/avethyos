pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Permanent typed clipboard history. Media payloads and their PNG previews are
// kept beside the JSON index; wl-paste remains event-driven rather than polled.
QtObject {
    id: root

    readonly property string dir: Config.stateDir
    readonly property string file: dir + "/clipboard.json"
    readonly property string mediaDir: dir + "/clipboard-media"
    readonly property string helper: Quickshell.shellPath("scripts/clipboard.py")
    property var entries: []
    property bool loaded: false
    property bool available: false
    property bool directoryReady: false

    readonly property var orderedEntries: entries.slice().sort(function(a, b) {
        if (a.pinned !== b.pinned)
            return a.pinned ? -1 : 1;
        return b.at - a.at;
    })
    readonly property int pinnedCount: entries.filter(function(item) {
        return item.pinned;
    }).length
    readonly property int historyCount: entries.length - pinnedCount

    function startWatcher(): void {
        if (loaded && available && directoryReady && !watcher.running)
            watcher.running = true;
    }

    function finishInitialLoad(items): void {
        if (loaded)
            return;
        entries = items;
        loaded = true;
        startWatcher();
    }

    function receive(line): void {
        let captured = null;
        try {
            captured = JSON.parse(String(line || ""));
        } catch (error) {
            return;
        }
        if (!captured || (captured.kind !== "text" &&
                          captured.kind !== "image" && captured.kind !== "video"))
            return;

        let pinned = false;
        const next = [];
        const duplicateKey = captured.kind === "text" ? captured.text : captured.payload;
        for (let i = 0; i < entries.length; ++i) {
            const itemKey = entries[i].kind === "text" ? entries[i].text : entries[i].payload;
            if (itemKey === duplicateKey)
                pinned = pinned || entries[i].pinned;
            else
                next.push(entries[i]);
        }
        captured.id = String(Date.now()) + "-" + String(Math.random()).slice(2);
        captured.pinned = pinned;
        captured.at = Date.now();
        next.push(captured);
        entries = next;
        persist();
    }

    function copy(entry): void {
        if (!entry)
            return;
        if (entry.kind === "text") {
            Quickshell.clipboardText = entry.text;
            return;
        }
        restoreProcess.command = ["python3", root.helper, "restore",
                                  entry.payload, entry.mime];
        restoreProcess.running = true;
    }

    function setPinned(id, pinned): void {
        const key = String(id);
        entries = entries.map(function(item) {
            if (item.id !== key)
                return item;
            return {
                id: item.id,
                kind: item.kind,
                text: item.text,
                mime: item.mime,
                payload: item.payload,
                preview: item.preview,
                label: item.label,
                pinned: Boolean(pinned),
                at: item.at
            };
        });
        persist();
    }

    function remove(id): void {
        const key = String(id);
        // A pin must be explicitly unpinned before it can be deleted.
        entries = entries.filter(function(item) {
            return item.id !== key || item.pinned;
        });
        persist();
    }

    function clearHistory(): void {
        entries = entries.filter(function(item) { return item.pinned; });
        persist();
    }

    function persist(): void {
        if (loaded)
            store.setText(JSON.stringify(entries, null, 2) + "\n");
    }

    property Process ensureDir: Process {
        command: ["mkdir", "-p", root.dir]
        running: true
        onExited: function(exitCode) {
            root.directoryReady = exitCode === 0;
            root.startWatcher();
        }
    }

    property FileView store: FileView {
        path: root.file
        printErrors: false
        watchChanges: false
        blockLoading: true
        preload: true

        onLoaded: {
            const raw = (store.text() || "").trim();
            try {
                const parsed = raw.length ? JSON.parse(raw) : [];
                root.entries = Array.isArray(parsed) ? parsed.filter(function(item) {
                    return item && ((typeof item.text === "string" && item.text.length) ||
                        (typeof item.payload === "string" && typeof item.preview === "string"));
                }).map(function(item) {
                    return {
                        id: String(item.id || (Date.now() + "-legacy")),
                        kind: String(item.kind || "text"),
                        text: String(item.text || ""),
                        mime: String(item.mime || ""),
                        payload: String(item.payload || ""),
                        preview: String(item.preview || ""),
                        label: String(item.label || item.mime || ""),
                        pinned: Boolean(item.pinned),
                        at: Number(item.at) || Date.now()
                    };
                }) : [];
            } catch (error) {
                root.entries = [];
            }
            root.finishInitialLoad(root.entries);
        }

        // A missing file is the normal first-run state, not a reason to leave
        // clipboard capture disabled. The first clipboard event creates it.
        onLoadFailed: {
            root.finishInitialLoad([]);
        }
    }

    property Process availabilityProbe: Process {
        command: ["sh", "-c", "command -v wl-paste >/dev/null && command -v wl-copy >/dev/null"]
        running: true
        onExited: function(exitCode) {
            root.available = exitCode === 0;
            root.startWatcher();
        }
    }

    property Process restoreProcess: Process {}

    // The helper emits one JSON line, while binary data stays in durable files.
    property Process watcher: Process {
        command: [
            "wl-paste", "--watch", "python3", root.helper, "capture", root.mediaDir
        ]
        stdout: SplitParser {
            onRead: function(line) { root.receive(line); }
        }
    }
}
