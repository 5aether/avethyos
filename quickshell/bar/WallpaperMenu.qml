import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../components"
import "../widgets"

Item {
    id: root
    property bool active: true
    property string filter: "all"
    implicitHeight: 550

    readonly property var visibleEntries: {
        const search = searchField.text.trim().toLocaleLowerCase();
        return WallpaperLibrary.entries.filter(function(entry) {
            return (!search.length || entry.name.toLocaleLowerCase().indexOf(search) >= 0)
                && (entry.directory || root.filter === "all" || entry.kind === root.filter);
        });
    }
    readonly property string currentName: {
        const path = WallpaperManager.requestedPath;
        if (!path.length)
            return "Choose your background";
        try { return decodeURIComponent(path.slice(path.lastIndexOf("/") + 1)); }
        catch (failure) { return path.slice(path.lastIndexOf("/") + 1); }
    }

    function activate(entry) {
        if (entry.directory) {
            searchField.text = "";
            WallpaperLibrary.browse(entry.url);
            grid.positionViewAtBeginning();
        } else {
            WallpaperManager.setPath(entry.url);
        }
    }

    onActiveChanged: WallpaperLibrary.active = active
    Component.onCompleted: WallpaperLibrary.active = active
    Component.onDestruction: WallpaperLibrary.active = false

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 84
            radius: 22
            color: Theme.popupSurface0

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                ClippingRectangle {
                    Layout.preferredWidth: 82
                    Layout.fillHeight: true
                    radius: 14
                    color: Theme.popupSurface2
                    Image {
                        anchors.fill: parent
                        source: WallpaperLibrary.currentThumbnail
                        sourceSize.width: 320
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !WallpaperLibrary.currentThumbnail.length
                        text: "wallpaper"
                        color: Theme.colors.mauve
                        font.family: Theme.iconFamily
                        font.pixelSize: 29
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    Text {
                        text: "YOUR WALLPAPER"
                        color: Theme.colors.textDim
                        font.family: Theme.textFamily
                        font.pixelSize: 9
                        font.letterSpacing: 1
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.currentName
                        textFormat: Text.PlainText
                        color: Theme.colors.text
                        font.family: Theme.textFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                    }
                    Text {
                        text: WallpaperManager.enabled ? "Visible on every display" : "Wallpaper paused"
                        color: Theme.colors.textDim
                        font.family: Theme.textFamily
                        font.pixelSize: 9
                    }
                }
                ControlSwitch {
                    label: "Show wallpaper"
                    checked: WallpaperManager.enabled
                    onToggled: value => WallpaperManager.setEnabled(value)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: "How it fits"
                color: Theme.colors.textDim
                font.family: Theme.textFamily
                font.pixelSize: 11
            }
            Repeater {
                model: [
                    {label: "Cover", value: "cover", icon: "crop_free"},
                    {label: "Fit", value: "fit", icon: "fit_screen"},
                    {label: "Stretch", value: "stretch", icon: "aspect_ratio"}
                ]
                ControlButton {
                    required property var modelData
                    label: modelData.label
                    accent: Config.wallpaperFillMode === modelData.value
                    implicitHeight: 31
                    onClicked: WallpaperManager.setFillMode(modelData.value === "fit" ? Image.PreserveAspectFit
                        : modelData.value === "stretch" ? Image.Stretch : Image.PreserveAspectCrop)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ControlButton {
                icon: "arrow_upward"
                enabled: !WallpaperLibrary.atRoot && !WallpaperLibrary.loading
                Accessible.name: "Parent folder"
                onClicked: {
                    searchField.text = "";
                    WallpaperLibrary.up();
                    grid.positionViewAtBeginning();
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    Layout.fillWidth: true
                    text: WallpaperLibrary.relativeDirectory === "." ? "Wallpaper library" : WallpaperLibrary.relativeDirectory
                    textFormat: Text.PlainText
                    font.family: Theme.textFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.colors.text
                    elide: Text.ElideMiddle
                }
                Text {
                    Layout.fillWidth: true
                    text: WallpaperLibrary.loading ? "Reading your folder…"
                        : root.visibleEntries.length + " items" + (WallpaperLibrary.thumbnailBusy ? " · preparing previews" : "")
                    font.family: Theme.textFamily
                    font.pixelSize: 9
                    color: Theme.colors.textDim
                    elide: Text.ElideRight
                }
            }
            ControlButton {
                visible: !WallpaperLibrary.atRoot
                icon: "home"
                Accessible.name: "Wallpaper library root"
                onClicked: {
                    searchField.text = "";
                    WallpaperLibrary.home();
                    grid.positionViewAtBeginning();
                }
            }
            ControlButton {
                icon: "refresh"
                busy: WallpaperLibrary.loading
                Accessible.name: "Refresh wallpapers"
                onClicked: WallpaperLibrary.refresh()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 20
            color: Theme.popupSurface1
            border.width: searchField.activeFocus ? 1 : 0
            border.color: Theme.colors.mauve
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 13
                anchors.rightMargin: 12
                spacing: 8
                Text {
                    text: "search"
                    font.family: Theme.iconFamily
                    font.pixelSize: 20
                    color: Theme.colors.textDim
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Find a wallpaper…"
                        visible: !searchField.text.length
                        color: Theme.colors.textDim
                        font.family: Theme.textFamily
                        font.pixelSize: 11
                    }
                    TextInput {
                        id: searchField
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.textFamily
                        font.pixelSize: 11
                        color: Theme.colors.text
                        selectionColor: Theme.colors.mauve
                        selectedTextColor: Theme.colors.crust
                        clip: true
                        selectByMouse: true
                        activeFocusOnTab: true
                        Accessible.name: "Search wallpaper library"
                        onTextChanged: grid.positionViewAtBeginning()
                    }
                }
                Text {
                    visible: searchField.text.length > 0
                    text: "close"
                    font.family: Theme.iconFamily
                    font.pixelSize: 17
                    color: Theme.colors.textDim
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -7
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchField.text = ""
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{label: "All", value: "all"}, {label: "Images", value: "image"}, {label: "Videos", value: "video"}]
                ControlButton {
                    required property var modelData
                    label: modelData.label
                    accent: root.filter === modelData.value
                    implicitHeight: 29
                    onClicked: {
                        root.filter = modelData.value;
                        grid.positionViewAtBeginning();
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 130
            clip: true

            GridView {
                id: grid
                anchors.fill: parent
                visible: !WallpaperLibrary.error.length && root.visibleEntries.length > 0
                model: root.visibleEntries
                cellWidth: width / 2
                cellHeight: 150
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 2500
                cacheBuffer: 150
                delegate: Item {
                    id: card
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight
                    readonly property bool selected: !modelData.directory && WallpaperLibrary.isCurrent(modelData.url)
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: (modelData.directory ? "Open folder " : "Apply wallpaper ") + modelData.name
                    Accessible.onPressAction: root.activate(modelData)
                    Keys.onReturnPressed: root.activate(modelData)
                    Keys.onSpacePressed: root.activate(modelData)

                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: 8
                        anchors.bottomMargin: 8
                        radius: 19
                        color: pointer.containsMouse || card.selected ? Theme.popupSurface2 : Theme.popupSurface0
                        border.width: card.selected || card.activeFocus ? 2 : 0
                        border.color: Theme.colors.mauve
                        scale: pointer.pressed ? 0.97 : 1
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                        ClippingRectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 5
                            height: 93
                            radius: 15
                            color: Theme.popupSurface1
                            Image {
                                id: thumbnail
                                anchors.fill: parent
                                source: WallpaperLibrary.thumbnailFor(card.modelData.url, card.modelData.thumbnail)
                                sourceSize.width: 320
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: thumbnail.status !== Image.Ready
                                text: card.modelData.directory ? "folder" : card.modelData.kind === "video" ? "movie" : "image"
                                font.family: Theme.iconFamily
                                font.pixelSize: card.modelData.directory ? 38 : 30
                                color: card.modelData.directory ? Theme.colors.mauve : Theme.colors.textDim
                                opacity: card.modelData.directory ? 1 : 0.55
                            }
                            Rectangle {
                                visible: card.modelData.kind === "video" || card.selected
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 6
                                width: 24
                                height: 24
                                radius: 12
                                color: card.selected ? Theme.colors.mauve : Qt.rgba(0, 0, 0, 0.65)
                                Text {
                                    anchors.centerIn: parent
                                    text: card.selected ? "check" : "play_arrow"
                                    font.family: Theme.iconFamily
                                    font.pixelSize: 16
                                    color: card.selected ? Theme.colors.crust : "white"
                                }
                            }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 11
                            anchors.rightMargin: 11
                            anchors.bottomMargin: 9
                            height: 31
                            text: card.modelData.name
                            textFormat: Text.PlainText
                            font.family: Theme.textFamily
                            font.pixelSize: 10
                            font.weight: card.selected ? Font.DemiBold : Font.Normal
                            color: Theme.colors.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        MouseArea {
                            id: pointer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activate(card.modelData)
                        }
                    }
                }
            }

            Item {
                id: scrollIndicator
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 3
                width: 3
                visible: grid.visible && grid.contentHeight > grid.height + 1
                opacity: grid.moving ? 0.85 : 0.38
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Rectangle {
                    width: parent.width
                    height: Math.max(26, parent.height * grid.height / Math.max(1, grid.contentHeight))
                    y: Math.max(0, Math.min(1, (grid.contentY - grid.originY)
                        / Math.max(1, grid.contentHeight - grid.height))) * (parent.height - height)
                    radius: width / 2
                    color: Theme.colors.textDim
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 28
                visible: WallpaperLibrary.error.length > 0 || root.visibleEntries.length === 0
                spacing: 9
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: WallpaperLibrary.loading ? "hourglass_top" : WallpaperLibrary.error.length ? "folder_off" : "photo_library"
                    color: Theme.colors.mauve
                    font.family: Theme.iconFamily
                    font.pixelSize: 34
                }
                Text {
                    Layout.fillWidth: true
                    text: WallpaperLibrary.loading ? "Opening your library…" : WallpaperLibrary.error.length ? WallpaperLibrary.error
                        : searchField.text.length || root.filter !== "all" ? "No matching wallpapers" : "Your wallpaper folder is empty"
                    textFormat: Text.PlainText
                    color: Theme.colors.text
                    font.family: Theme.textFamily
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: !WallpaperLibrary.loading
                    text: WallpaperLibrary.error.length || WallpaperLibrary.entries.length === 0
                        ? Config.wallpaperFolder : "Try another name or media type"
                    textFormat: Text.PlainText
                    color: Theme.colors.textDim
                    font.family: Theme.textFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                ControlButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: WallpaperLibrary.error.length > 0
                    label: "Try again"
                    icon: "refresh"
                    onClicked: WallpaperLibrary.refresh()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: WallpaperManager.error.length > 0
            text: WallpaperManager.error
            textFormat: Text.PlainText
            color: Theme.colors.red
            font.family: Theme.textFamily
            font.pixelSize: 10
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
}
