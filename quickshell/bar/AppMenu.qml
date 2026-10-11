import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import "../components"
import "../widgets"
import "../modules/appSearch.js" as AppSearch

Rectangle {
    id: root

    // Keep the launcher on the same output as its bar.
    property var launcherScreen: null
    property real availableWidth: 900
    property real availableHeight: 700
    property bool popupOpen: false

    function togglePopup(): void {
        root.popupOpen = !root.popupOpen;
    }

    function launch(entry, action): void {
        AppUsage.record(AppSearch.appKey(entry));
        if (action)
            action.execute();
        else
            entry.execute();
        root.popupOpen = false;
    }

    function closeAppMenu(): void {
        if (!actionMenu || actionMenu.entry === null)
            return;
        actionMenu.entry = null;
        if (root.popupOpen)
            search.forceActiveFocus();
    }

    function openAppMenu(entry, item, x, y): void {
        actionMenu.open(entry, item.mapToItem(popup.contentItem, x, y));
    }

    Connections {
        target: AppSearchIndex
        function onCatalogChanged() { root.closeAppMenu(); }
    }

    PopupFocus {
        popupWindow: popup
        opened: root.popupOpen
        dismissAction: function() { root.popupOpen = false; }
    }
    PopupMotion {
        id: popupMotion
        opened: root.popupOpen
    }

    width: 42
    height: 30
    radius: Theme.radius
    color: root.popupOpen || mouseArea.containsMouse ? Theme.popupSurface1 : Theme.popupSurface0
    border.width: root.popupOpen ? 1 : 0
    border.color: Theme.colors.blue
    Behavior on color { ColorAnimation { duration: 140 } }

    Text {
        anchors.centerIn: parent
        text: "apps"
        color: Theme.colors.blue
        font.family: Theme.iconFamily
        font.pixelSize: 20
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.togglePopup()
    }

    PanelWindow {
        id: popup
        readonly property int cornerRadius: 20
        visible: popupMotion.active
        property bool opened: root.popupOpen
        screen: root.launcherScreen
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        // Request compositor keyboard focus even when opened through IPC.
        WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: opened ? null : closingMask
        Region { id: closingMask }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        onOpenedChanged: {
            root.closeAppMenu();
            if (!opened)
                return;
            AppSearchIndex.refresh();
            search.text = "";
            // Reset explicitly even when the search was already empty.
            apps.currentIndex = apps.count > 0 ? 0 : -1;
            apps.positionViewAtBeginning();
            search.forceActiveFocus();
            Qt.callLater(() => {
                if (root.popupOpen)
                    search.forceActiveFocus();
            });
        }

        color: "transparent"

        AttachedGlass {
            screen: popup.screen
            sourceWindow: popup
            standaloneParent: popup.contentItem
            globalY: 0
            active: popupMotion.active
            x: panel.x
            y: panel.y
            width: panel.width
            height: panel.height
            cornerRadius: popup.cornerRadius
            attachRightEdge: false
            flowStrength: 0
            joinProgress: popupMotion.joinProgress
            revealProgress: popupMotion.expansionProgress
            color: Theme.barBackground
        }

        // Full-screen MouseArea to catch clicks outside the panel
        MouseArea {
            anchors.fill: parent
            enabled: root.popupOpen
            onPressed: mouse => {
                const point = panel.mapFromItem(parent, mouse.x, mouse.y);
                if (!panel.contains(point) || point.y >= panel.revealedHeight) {
                    root.popupOpen = false;
                    mouse.accepted = true;
                } else {
                    mouse.accepted = false;
                }
            }
        }

        AttachedPanel {
            id: panel
            enabled: root.popupOpen
            anchors.horizontalCenter: parent.horizontalCenter
            y: OverlayService.topMargin(popup.screen)
            width: Math.min(640, Math.max(480, root.availableWidth - 120))
                + 2 * popup.cornerRadius
            height: Math.min(520, Math.max(400, root.availableHeight - 200))
                + popup.cornerRadius - 6
            cornerRadius: popup.cornerRadius
            attachRightEdge: false
            flowStrength: 0
            joinProgress: popupMotion.joinProgress
            revealProgress: popupMotion.expansionProgress
            contentOpacity: popupMotion.contentOpacity
            color: "transparent"

            // Clip pointer delivery to the part grown from the bar.
            // Keep the inner layout fixed while the viewport expands.
            Item {
                width: panel.width
                height: panel.revealedHeight
                clip: true

                Item {
                    width: panel.width
                    height: panel.height

                    Rectangle {
                        id: searchBox
                        width: parent.width - 64 - 2 * popup.cornerRadius
                        height: 36
                        anchors.top: parent.top
                        anchors.topMargin: 16
                        anchors.horizontalCenter: parent.horizontalCenter
                        radius: Theme.radius
                        color: Theme.popupSurface0

                        Text {
                            id: searchIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 11
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search"
                            color: Theme.colors.textDim
                            font.family: Theme.iconFamily
                            font.pixelSize: 17
                        }

                        Text {
                            font.family: Theme.textFamily
                            anchors.fill: parent
                            anchors.leftMargin: 36
                            anchors.rightMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            visible: search.text.length === 0
                            text: "Search applications"
                            color: Theme.colors.textDim
                            font.pixelSize: 12
                        }

                        TextInput {
                            font.family: Theme.textFamily
                            id: search
                            focus: true
                            anchors.fill: parent
                            anchors.leftMargin: 36
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.colors.text
                            selectionColor: Theme.colors.blue
                            selectedTextColor: Theme.colors.crust
                            font.pixelSize: 12
                            clip: true
                            activeFocusOnPress: true
                            selectByMouse: true
                            onTextChanged: {
                                root.closeAppMenu();
                                apps.currentIndex = apps.count > 0 ? 0 : -1;
                            }
                            onAccepted: {
                                if (apps.count > 0) {
                                    const index = apps.currentIndex >= 0 ? apps.currentIndex : 0;
                                    root.launch(apps.model.values[index]);
                                }
                            }
                            Keys.onDownPressed: {
                                if (apps.count > 0)
                                    apps.currentIndex = Math.min(
                                        apps.count - 1,
                                        apps.currentIndex + apps.columns
                                    );
                            }
                            Keys.onUpPressed: {
                                if (apps.count > 0)
                                    apps.currentIndex = Math.max(0, apps.currentIndex - apps.columns);
                            }
                            Keys.onLeftPressed: {
                                if (apps.count > 0)
                                    apps.currentIndex = Math.max(0, apps.currentIndex - 1);
                            }
                            Keys.onRightPressed: {
                                if (apps.count > 0)
                                    apps.currentIndex = Math.min(apps.count - 1, apps.currentIndex + 1);
                            }
                            Keys.priority: Keys.BeforeItem
                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Menu
                                    || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                                    if (apps.currentItem) {
                                        const tile = apps.currentItem;
                                        root.openAppMenu(tile.modelData, tile, tile.width / 2, tile.height - 8);
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                    if (apps.count > 0)
                                        apps.currentIndex = Math.max(0, Math.min(apps.count - 1,
                                            apps.currentIndex + (event.key === Qt.Key_Tab ? 1 : -1)));
                                    event.accepted = true;
                                }
                            }
                            Keys.onEscapePressed: root.popupOpen = false
                        }
                    }

                    Rectangle {
                        id: separator
                        anchors.top: searchBox.bottom
                        anchors.topMargin: 14
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 32 + popup.cornerRadius
                        anchors.rightMargin: 32 + popup.cornerRadius
                        height: 1
                        color: Qt.rgba(Theme.popupSurface1.r, Theme.popupSurface1.g,
                                       Theme.popupSurface1.b, 0.55)
                    }

                    Item {
                        id: resultsArea
                        anchors.top: separator.bottom
                        anchors.topMargin: 8
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 16 + popup.cornerRadius
                        anchors.rightMargin: 16 + popup.cornerRadius
                        anchors.bottomMargin: 14 + popup.cornerRadius

                        GridView {
                            id: apps
                            readonly property int columns: Math.max(4, Math.floor(width / 108))
                            readonly property bool searching: search.text.trim().length > 0

                            // Keep the tiles at their normal size and center each row,
                            // including the final row when it is only partly filled.
                            function rowOffset(index): real {
                                if (!searching || index < 0)
                                    return 0;
                                const rowStart = Math.floor(index / columns) * columns;
                                const rowCount = Math.min(columns, count - rowStart);
                                return (columns - rowCount) * cellWidth / 2;
                            }

                            anchors.centerIn: parent
                            width: parent.width
                            height: searching && count > 0
                                ? Math.min(parent.height, Math.ceil(count / columns) * cellHeight)
                                : parent.height
                            clip: true
                            cellWidth: width / columns
                            cellHeight: 104
                            highlightMoveDuration: 100
                            highlightFollowsCurrentItem: true
                            currentIndex: count > 0 ? 0 : -1
                            onCountChanged: {
                                root.closeAppMenu();
                                currentIndex = count > 0 ? 0 : -1;
                            }
                            model: ScriptModel {
                                values: {
                                    // Reading revision makes this binding refresh after
                                    // a launch or after the persisted counts load.
                                    const usageRevision = AppUsage.revision;
                                    return AppSearch.rankApps(
                                        AppSearchIndex.applications,
                                        search.text,
                                        AppUsage.counts,
                                        AppSearchIndex.entries
                                    );
                                }
                            }

                            highlight: Rectangle {
                                transform: Translate { x: apps.rowOffset(apps.currentIndex) }
                                radius: Theme.radius
                                color: Theme.popupSurface0
                                opacity: 0.8
                            }

                            delegate: Item {
                                id: appTile
                                required property var modelData
                                required property int index
                                width: apps.cellWidth
                                height: apps.cellHeight
                                transform: Translate { x: apps.rowOffset(appTile.index) }

                                function launch() {
                                    root.launch(modelData);
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    radius: Theme.radius
                                    color: appMouse.containsMouse && apps.currentIndex !== index
                                        ? Theme.popupSurface0 : "transparent"
                                    opacity: appMouse.containsMouse ? 0.55 : 1
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Image {
                                    id: appIcon
                                    anchors.top: parent.top
                                    anchors.topMargin: 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 56
                                    height: 56
                                    source: IconThemeService.resolve(
                                        appTile.modelData.icon || "application-x-executable",
                                        "application-x-executable"
                                    )
                                    fillMode: Image.PreserveAspectFit
                                    // Never hold up the popup while image files are being
                                    // decoded. Loading icons stay transparent and appear
                                    // when ready, rather than flashing placeholders.
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    visible: status === Image.Ready
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 80 } }
                                    // Gentle lift on hover: the icon scales up a touch.
                                    scale: appMouse.containsMouse ? 1.08 : 1
                                    Behavior on scale {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                }

                                Rectangle {
                                    anchors.fill: appIcon
                                    radius: Theme.radius
                                    color: Theme.popupSurface1
                                    // This is an actual missing-icon fallback, never a
                                    // temporary loading placeholder.
                                    visible: appIcon.status === Image.Error
                                             || (appIcon.status === Image.Null
                                                 && appIcon.source.toString().length === 0)
                                    scale: appMouse.containsMouse ? 1.08 : 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "apps"
                                        color: Theme.colors.mauve
                                        font.family: Theme.iconFamily
                                        font.pixelSize: 30
                                    }

                                    Behavior on scale {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                }

                                Text {
                                    font.family: Theme.textFamily
                                    anchors.top: appIcon.bottom
                                    anchors.topMargin: 7
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    horizontalAlignment: Text.AlignHCenter
                                    text: appTile.modelData.name
                                    color: Theme.colors.text
                                    elide: Text.ElideRight
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: appMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        apps.currentIndex = index;
                                        if (mouse.button === Qt.RightButton)
                                            root.openAppMenu(appTile.modelData, appTile, mouse.x, mouse.y);
                                        else
                                            appTile.launch();
                                    }
                                }
                            }

                            Text {
                                font.family: Theme.textFamily
                                anchors.centerIn: parent
                                visible: apps.count === 0 && search.text.length > 0
                                text: "No applications found"
                                color: Theme.colors.textDim
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: 9
            visible: actionMenu.entry !== null
            acceptedButtons: Qt.AllButtons
            onPressed: root.closeAppMenu()
            onWheel: wheel => {
                root.closeAppMenu();
                wheel.accepted = true;
            }
        }

        AppActionMenu {
            id: actionMenu
            z: 10
            onDismissed: root.closeAppMenu()
            onTriggered: action => root.launch(entry, action)
        }
    }
}
