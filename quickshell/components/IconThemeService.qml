pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Resolves icons from the configured pack and its inheritance chain. An empty
// config value follows GTK's settings; gsettings monitoring is event-driven.
QtObject {
    id: root
    readonly property int resolverVersion: 4

    property string themeName: ""
    property string gtk3Theme: ""
    property string gtk4Theme: ""
    property string settingsTheme: ""
    property var icons: ({})
    property int revision: 0
    property bool rebuildPending: false

    function resolve(value, fallback) {
        const icon = String(value || "");
        if (!icon.length)
            return "";
        if (icon.startsWith("/"))
            return "file://" + icon + "?gtkThemeRevision=" + revision;
        if (icon.startsWith("file:"))
            return icon + (icon.indexOf("?") >= 0 ? "&" : "?") + "gtkThemeRevision=" + revision;
        if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(icon))
            return icon;
        // Desktop files are inconsistent here: some include an image suffix,
        // and some use different casing than the icon theme. The scanner
        // publishes normalized aliases so those still resolve to the real
        // application icon.
        const name = icon.replace(/\.(png|svg|xpm)$/i, "");
        const path = icons[name] || icons[name.toLowerCase()];
        if (path)
            return "file://" + path + "?gtkThemeRevision=" + revision;

        // The theme index is built in the background. Ask Qt's native icon
        // provider before falling back so the first launcher open does not
        // have to wait for that scan. This also resolves an icon installed
        // after the index was built immediately, on its very first use.
        const nativePath = Quickshell.iconPath(name, true);
        if (nativePath)
            return nativePath;

        const fallbackPath = icons[String(fallback || "application-x-executable")];
        if (fallbackPath)
            return "file://" + fallbackPath + "?gtkThemeRevision=" + revision;

        const nativeFallback = Quickshell.iconPath(
            String(fallback || "application-x-executable"), true
        );
        if (nativeFallback)
            return nativeFallback;
        // An empty source lets each UI provide its own built-in glyph without
        // sending a known-missing name through Qt's icon provider (and logging
        // a warning for every occurrence).
        return "";
    }

    function queryTheme() {
        if (!themeQuery.running)
            themeQuery.running = true;
    }

    function themeFromSettings(text) {
        const match = String(text || "").match(/^\s*gtk-icon-theme-name\s*=\s*(.+?)\s*$/m);
        return match ? match[1].trim().replace(/^['\"]|['\"]$/g, "") : "";
    }

    function selectTheme() {
        // nwg-look writes GTK's settings.ini files. Prefer those over the
        // GNOME dconf value, which may still contain Adwaita on wlroots.
        const selected = Config.iconPack || gtk3Theme || gtk4Theme || settingsTheme || "hicolor";
        if (selected.length && selected !== themeName) {
            themeName = selected;
            // Do not keep icons from the previous pack while the new one loads.
            icons = ({});
            revision += 1;
            rebuild();
        }
    }

    Component.onCompleted: {
        selectTheme();
        desktopSync.restart();
    }

    property Connections configChanges: Connections {
        target: Config
        function onIconPackChanged() {
            root.selectTheme();
            desktopSync.restart();
        }
    }

    // Coalesce edits and serialize them with wallpaper updates in the helper.
    // Reading Config.file at execution time also handles another edit arriving
    // while the previous sync is still running.
    property bool desktopSyncPending: false
    property Timer desktopSync: Timer {
        interval: 100
        onTriggered: {
            if (desktopTheme.running)
                root.desktopSyncPending = true;
            else
                desktopTheme.running = true;
        }
    }

    property Process desktopTheme: Process {
        command: ["python3", Quickshell.shellPath("scripts/material-palette.py"),
                  "--icons-only", "--config", Config.file]
        onExited: function(exitCode) {
            if (exitCode !== 0)
                console.error("Avethy: desktop icon theme sync failed (" + exitCode + ")");
            if (root.desktopSyncPending) {
                root.desktopSyncPending = false;
                desktopSync.restart();
            }
        }
    }

    property Connections installedFiles: Connections {
        target: DesktopFileMonitor
        function onIconsChanged() { iconRefresh.restart(); }
    }

    property Timer iconRefresh: Timer {
        interval: 60
        onTriggered: root.rebuild()
    }

    function rebuild() {
        if (!themeName.length)
            return;
        if (scanner.running) {
            rebuildPending = true;
            return;
        }
        rebuildPending = false;
        scanner.command = ["python3", Quickshell.shellPath("scripts/icon-theme.py"),
                           "--", themeName, String(resolverVersion)];
        scanner.targetTheme = themeName;
        scanner.running = true;
    }

    property Process themeQuery: Process {
        command: ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim().replace(/^['\"]|['\"]$/g, "");
                root.settingsTheme = name;
                root.selectTheme();
            }
        }
    }


    property FileView gtk3Settings: FileView {
        path: Quickshell.env("HOME") + "/.config/gtk-3.0/settings.ini"
        printErrors: false
        watchChanges: true
        preload: true
        onLoaded: {
            root.gtk3Theme = root.themeFromSettings(text());
            root.selectTheme();
        }
        onFileChanged: reload()
    }

    property FileView gtk4Settings: FileView {
        path: Quickshell.env("HOME") + "/.config/gtk-4.0/settings.ini"
        printErrors: false
        watchChanges: true
        preload: true
        onLoaded: {
            root.gtk4Theme = root.themeFromSettings(text());
            root.selectTheme();
        }
        onFileChanged: reload()
    }

    property Process themeMonitor: Process {
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "icon-theme"]
        running: true
        stdout: SplitParser { onRead: root.queryTheme() }
    }

    property Process scanner: Process {
        property string targetTheme: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (scanner.targetTheme === root.themeName) {
                        root.icons = JSON.parse(text || "{}");
                        root.revision += 1;
                    }
                } catch (error) {
                    root.icons = ({});
                }
            }
        }
        onExited: {
            if (root.rebuildPending || scanner.targetTheme !== root.themeName)
                Qt.callLater(root.rebuild);
        }
    }
}
