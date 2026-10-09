import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../components"

RowLayout {
    id: root
    spacing: 6

    property bool leftSuperHeld: false
    property bool rightSuperHeld: false
    readonly property bool showApps: !(leftSuperHeld || rightSuperHeld)

    // Hyprland forwards both edges of each Super key over its event socket.
    // Return to icons after both Super keys have been released.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "custom")
                return;
            const parts = event.data.split(",");
            if (parts[0] !== "quickshell-workspace-apps")
                return;
            if (parts[1] === "left")
                root.leftSuperHeld = parts[2] === "1";
            else if (parts[1] === "right")
                root.rightSuperHeld = parts[2] === "1";
            else if (parts[1] === "reset") {
                root.leftSuperHeld = false;
                root.rightSuperHeld = false;
            }
        }
    }

    function applicationsFor(workspace) {
        if (!workspace)
            return [];
        const desktopEntries = DesktopEntries.applications.values;
        const apps = [];
        const seen = new Set();
        for (const window of workspace.toplevels.values) {
            const ipc = window.lastIpcObject || {};
            const classes = [window.wayland ? window.wayland.appId : "",
                             ipc.class, ipc.initialClass].filter(Boolean);
            let entry = null;
            for (const appClass of classes) {
                entry = desktopEntries.find(app => app.startupClass
                    && app.startupClass.toLowerCase() === appClass.toLowerCase())
                    || DesktopEntries.heuristicLookup(appClass);
                if (entry)
                    break;
            }
            const key = entry ? entry.id : (classes[0] || window.address);
            if (seen.has(key))
                continue;
            seen.add(key);
            apps.push({ name: entry ? entry.name : (classes[0] || "App"),
                        icon: entry && entry.icon ? entry.icon
                            : (classes[0] || "application-x-executable") });
        }
        return apps.sort((a, b) => a.name.localeCompare(b.name));
    }

    Repeater {
        model: Hyprland.workspaces.values
            .filter(workspace => workspace.id >= 1 && workspace.id <= 10
                && (workspace.focused || workspace.toplevels.values.length > 0))
            .map(workspace => workspace.id)
            .sort((a, b) => a - b)

        Rectangle {
            id: workspaceButton
            required property int modelData
            readonly property var workspace: Hyprland.workspaces.values
                .find(workspace => workspace.id === modelData) || null
            readonly property bool isFocused: workspace ? workspace.focused : false
            readonly property var apps: root.applicationsFor(workspace)
            readonly property bool showAppIcons: root.showApps && apps.length > 0

            implicitWidth: showAppIcons ? Math.max(26, appIcons.implicitWidth + 8) : 26
            implicitHeight: 26
            Layout.preferredWidth: implicitWidth
            radius: Theme.radius
            color: isFocused ? Theme.colors.mauve
                   : workspaceMouse.containsMouse ? Theme.colors.surface1
                   : Theme.colors.surface0
            scale: workspaceMouse.pressed ? 0.9 : 1

            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on scale {
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
            }
            Behavior on implicitWidth {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            Text {
                font.family: Theme.textFamily
                anchors.centerIn: parent
                text: workspaceButton.modelData
                opacity: workspaceButton.showAppIcons ? 0 : 1
                visible: opacity > 0
                color: workspaceButton.isFocused ? Theme.colors.crust : Theme.colors.text
                font.bold: true
                font.pixelSize: 11

                Behavior on opacity {
                    NumberAnimation { duration: 140; easing.type: Easing.InOutQuad }
                }
            }

            Row {
                id: appIcons
                anchors.centerIn: parent
                spacing: 4
                opacity: workspaceButton.showAppIcons ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: 140; easing.type: Easing.InOutQuad }
                }

                Repeater {
                    model: workspaceButton.apps
                    Item {
                        id: appIcon
                        required property var modelData
                        width: 18
                        height: 18

                        Image {
                            id: iconImage
                            anchors.fill: parent
                            source: IconThemeService.resolve(appIcon.modelData.icon)
                            sourceSize.width: 36
                            sourceSize.height: 36
                            fillMode: Image.PreserveAspectFit
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: iconImage.status !== Image.Ready
                            text: appIcon.modelData.name.charAt(0).toUpperCase()
                            font.family: Theme.textFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: workspaceButton.isFocused ? Theme.colors.crust : Theme.colors.text
                        }
                    }
                }
            }

            MouseArea {
                id: workspaceMouse
                anchors.fill: parent
                onClicked: {
                    if (workspaceButton.workspace)
                        workspaceButton.workspace.activate();
                }

                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
            }
        }
    }
}
