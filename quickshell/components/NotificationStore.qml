pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Permanent, user-owned notification history.
//
// Stored in ~/.local/share/quickshell/notifications.json as a plain JSON array,
// newest first. Entries are only ever removed when the user explicitly clears
// them, so they survive `qs` restarts, reboots and power loss.
//
// The NotificationServer keeps nothing of its own: this file is the single
// source of truth for the history list.
QtObject {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/share/quickshell"
    readonly property string file: dir + "/notifications.json"

    // Newest first.
    property var entries: []
    // True once the file has been read, so a write before the first load does
    // not clobber existing history with an empty array.
    property bool loaded: false

    // Accepts either a raw path or a file:// URL.
    function normalize(url) {
        return url ? String(url) : "";
    }

    // qsimage is an in-memory handle owned by a live Notification. It cannot
    // be restored from JSON and must never be placed in permanent history.
    function durableImage(url) {
        const value = root.normalize(url);
        return value.startsWith("image://qsimage/") ? "" : value;
    }

    function add(id, summary, body, appName, appIcon, image, at) {
        const list = root.entries.slice();
        list.push({
            id: String(id),
            summary: summary ? String(summary) : "",
            body: body ? String(body) : "",
            appName: appName ? String(appName) : "",
            appIcon: root.normalize(appIcon),
            image: root.durableImage(image),
            at: at ? Number(at) : Date.now()
        });
        // Newest first.
        list.sort(function (a, b) { return b.at - a.at; });
        root.entries = list;
        root.persist();
    }

    function remove(id) {
        const key = String(id);
        root.entries = root.entries.filter(function (item) { return item.id !== key; });
        root.persist();
    }

    function clear() {
        root.entries = [];
        root.persist();
    }

    function persist() {
        store.setText(JSON.stringify(root.entries, null, 2) + "\n");
    }

    // The directory must exist before the first write, and quickshell may not
    // have created ~/.local/share yet on a very fresh account. Quoted so a
    // home directory containing spaces or quotes cannot break the command.
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
            const raw = (store.text() || "").trim();
            if (raw.length) {
                try {
                    const parsed = JSON.parse(raw);
                    root.entries = Array.isArray(parsed) ? parsed.map(function(entry) {
                        entry.image = root.durableImage(entry.image);
                        return entry;
                    }) : [];
                } catch (err) {
                    root.entries = [];
                }
            } else {
                root.entries = [];
            }
            root.loaded = true;
        }
    }
}
