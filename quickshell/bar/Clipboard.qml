import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../components"
import "../widgets"

Rectangle {
    id: root

    property bool popupOpen: false
    function togglePopup(): void { root.popupOpen = !root.popupOpen; }

    // Hidden - no visual presence in the bar
    width: 0
    height: 0
    visible: false

    PopupFocus {
        popupWindow: popup
        opened: root.popupOpen
        dismissAction: function() { root.popupOpen = false; }
    }
    PopupMotion {
        id: popupMotion
        opened: root.popupOpen
    }

    // Keep the input catcher fullscreen while the panel grows from the bar.
    PanelWindow {
        id: popup
        readonly property int cornerRadius: 20
        screen: root.QsWindow.window?.screen ?? null
        visible: popupMotion.active
        mask: root.popupOpen ? null : closingMask
        Region { id: closingMask }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:clipboard"
        WlrLayershell.layer: WlrLayer.Top

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        color: "transparent"

        AttachedGlass {
            screen: popup.screen
            sourceWindow: popup
            standaloneParent: popup.contentItem
            globalY: 0
            active: popupMotion.active
            x: clipboardPanel.x
            y: clipboardPanel.y
            width: clipboardPanel.width
            height: clipboardPanel.height
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
                const point = clipboardPanel.mapFromItem(parent, mouse.x, mouse.y);
                if (!clipboardPanel.contains(point)
                    || point.y >= clipboardPanel.revealedHeight) {
                    root.popupOpen = false;
                    mouse.accepted = true;
                } else {
                    mouse.accepted = false;
                }
            }
        }

        AttachedPanel {
            id: clipboardPanel
            enabled: root.popupOpen
            anchors.horizontalCenter: parent.horizontalCenter
            y: OverlayService.topMargin(popup.screen)
            width: 600 + 2 * popup.cornerRadius
            height: 500 + popup.cornerRadius
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
                width: clipboardPanel.width
                height: clipboardPanel.revealedHeight
                clip: true

                Item {
                    width: clipboardPanel.width
                    height: clipboardPanel.height

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        anchors.leftMargin: 14 + popup.cornerRadius
                        anchors.rightMargin: 14 + popup.cornerRadius
                        anchors.bottomMargin: 14 + popup.cornerRadius
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                font.family: Theme.textFamily
                                text: "Clipboard"
                                color: Theme.colors.text
                                font.pixelSize: 15
                                font.bold: true
                            }

                            Text {
                                font.family: Theme.textFamily
                                text: ClipboardService.entries.length
                                color: Theme.colors.textDim
                                font.pixelSize: 11
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredWidth: clearLabel.implicitWidth + 18
                                Layout.preferredHeight: 28
                                radius: Theme.radius
                                color: clearMouse.containsMouse
                                    ? Theme.popupSurface2 : Theme.popupSurface0
                                visible: ClipboardService.historyCount > 0

                                Text {
                                    font.family: Theme.textFamily
                                    id: clearLabel
                                    anchors.centerIn: parent
                                    text: "Clear history"
                                    color: Theme.colors.textDim
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    id: clearMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ClipboardService.clearHistory()
                                }
                            }
                        }

                        Text {
                            font.family: Theme.textFamily
                            Layout.fillWidth: true
                            visible: ClipboardService.pinnedCount > 0
                            text: ClipboardService.pinnedCount + " pinned · pins survive history clearing"
                            color: Theme.colors.mauve
                            font.pixelSize: 10
                        }

                        ListView {
                            id: clipboardList

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 6
                            visible: ClipboardService.entries.length > 0
                            model: ClipboardService.orderedEntries

                            delegate: Rectangle {
                                id: entryRow

                                required property var modelData
                                readonly property var entry: modelData
                                width: clipboardList.width
                                height: entryRow.entry.kind === "text"
                                    ? Math.max(64, textPreview.implicitHeight + 22) : 150
                                radius: Theme.radius
                                color: entryMouse.containsMouse
                                    ? Theme.popupSurface1 : Theme.popupSurface0
                                border.width: entry.pinned ? 1 : 0
                                border.color: Theme.colors.mauve
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    font.family: Theme.textFamily
                                    id: textPreview
                                    anchors.left: parent.left
                                    anchors.right: actions.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 10
                                    text: entryRow.entry.text || ""
                                    visible: entryRow.entry.kind === "text"
                                    textFormat: Text.PlainText
                                    color: Theme.colors.text
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }

                                Image {
                                    id: mediaPreview
                                    anchors.left: parent.left
                                    anchors.right: actions.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 10
                                    anchors.rightMargin: 10
                                    visible: entryRow.entry.kind !== "text"
                                    source: visible ? "file://" + entryRow.entry.preview : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: true
                                    // Fit-mode images can be smaller than this item;
                                    // round the painted image rather than its letterbox.
                                    layer.enabled: visible
                                    layer.effect: OpacityMask {
                                        maskSource: Item {
                                            width: mediaPreview.width
                                            height: mediaPreview.height
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: mediaPreview.paintedWidth
                                                height: mediaPreview.paintedHeight
                                                radius: Theme.radius
                                                color: "black"
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: entryRow.entry.kind === "video"
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 4
                                        width: videoLabel.implicitWidth + 12
                                        height: 22
                                        radius: Theme.radius
                                        color: Qt.rgba(0, 0, 0, 0.72)

                                        Text {
                                            id: videoLabel
                                            anchors.centerIn: parent
                                            text: "play_arrow  VIDEO"
                                            color: "white"
                                            font.family: Theme.iconFamily
                                            font.pixelSize: 11
                                        }
                                    }
                                }

                                Row {
                                    id: actions
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    Text {
                                        text: "push_pin"
                                        color: entryRow.entry.pinned
                                            ? Theme.colors.mauve : Theme.colors.textDim
                                        font.family: Theme.iconFamily
                                        font.pixelSize: 18

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -5
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: ClipboardService.setPinned(
                                                entryRow.entry.id, !entryRow.entry.pinned)
                                        }
                                    }

                                    Text {
                                        visible: !entryRow.entry.pinned
                                        text: "delete_outline"
                                        color: Theme.colors.textDim
                                        font.family: Theme.iconFamily
                                        font.pixelSize: 18

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -5
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: ClipboardService.remove(entryRow.entry.id)
                                        }
                                    }
                                }

                                MouseArea {
                                    id: entryMouse
                                    anchors.fill: parent
                                    anchors.rightMargin: 70
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        ClipboardService.copy(entryRow.entry);
                                        root.popupOpen = false;
                                    }
                                }
                            }
                        }

                        Text {
                            font.family: Theme.textFamily
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: ClipboardService.entries.length === 0
                            text: ClipboardService.available
                                ? "Copied text and media will appear here"
                                : "Install wl-clipboard to capture history"
                            color: Theme.colors.textDim
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
