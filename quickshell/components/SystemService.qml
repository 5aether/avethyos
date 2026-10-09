pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Host/user facts shared by UI components. Sources are reactive or read once.
QtObject {
    id: root

    readonly property string username: Quickshell.env("USER") || "User"
    property string fullName: username
    property double bootTimeMs: Date.now()
    readonly property string uptime: {
        const totalMinutes = Math.max(0, Math.floor((clock.date.getTime() - bootTimeMs) / 60000));
        const days = Math.floor(totalMinutes / 1440);
        const hours = Math.floor((totalMinutes % 1440) / 60);
        const minutes = totalMinutes % 60;
        return days > 0 ? days + "d " + hours + "h"
             : hours > 0 ? hours + "h " + minutes + "m" : minutes + "m";
    }

    property SystemClock clock: SystemClock { precision: SystemClock.Minutes }

    property FileView uptimeFile: FileView {
        path: "/proc/uptime"
        blockLoading: true
        preload: true
        printErrors: false
        onLoaded: {
            const seconds = Number((text() || "0").split(" ")[0]);
            if (isFinite(seconds))
                root.bootTimeMs = Date.now() - seconds * 1000;
        }
    }

    property Process userQuery: Process {
        running: true
        command: ["getent", "passwd", root.username]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split(":");
                if (fields.length >= 5) {
                    const name = fields[4].split(",")[0].trim();
                    root.fullName = name || root.username;
                }
            }
        }
    }

    property Process themeQuery: Process {
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: StdioCollector {
            onStreamFinished: Theme.darkMode = text.indexOf("dark") !== -1
        }
    }
}
