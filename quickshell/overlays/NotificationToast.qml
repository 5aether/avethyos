import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../components"
import "../widgets"

// Notification toasts share one attached panel, with the newest row on top.
//
// The model holds plain JS snapshots (see NotificationManager.pushToast), so a
// notification that its sender later closes can never invalidate a card that is
// still on screen.
PanelWindow {
    id: root

    // Resolves an icon to a loadable URL.
    //
    // IconImage.source is a plain alias to Image.source: it takes a URL and does
    // NOT resolve freedesktop icon names, so handing it a bare name like
    // "vesktop" would resolve it as a relative path against IconImage.qml's own
    // qrc directory. Quickshell.iconPath() is what turns a themed name into a
    // real URL, so it is used for names, while an absolute path or an existing
    // URL is passed through untouched.
    function iconSource(value) {
        const icon = String(value || "");
        if (!icon.length)
            return "";
        // A real path, or anything already carrying a scheme (file://, ...).
        if (icon.startsWith("/") || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(icon))
            return icon;
        return IconThemeService.resolve(icon, "application-x-executable");
    }

    readonly property var toasts: NotificationManager.visibleToasts
    readonly property int blendHeight: 36
    readonly property int motionDuration: 260
    readonly property bool shouldShow: toastModel.count > 0 && !OsdService.overlayVisible
    property bool panelOpened: false
    property var previousToasts: ({})

    // Updating a JS-array Repeater recreates every delegate. Reconcile by ID
    // instead, so existing rows retain their position and animation state.
    ListModel {
        id: toastModel
        dynamicRoles: true
    }

    function indexOfToast(id) {
        for (let i = 0; i < toastModel.count; ++i) {
            if (toastModel.get(i).toastId === String(id))
                return i;
        }
        return -1;
    }

    function updateReveal() {
        let active = false;
        for (let i = 0; i < toastRepeater.count; ++i) {
            const row = toastRepeater.itemAt(i);
            if (row && !row.dismissing) {
                active = true;
                break;
            }
        }
        panelOpened = active && !OsdService.overlayVisible;
    }

    function syncToasts() {
        const next = {};
        for (const toast of toasts)
            next[String(toast.id)] = toast;

        // Keep outgoing rows until their motion finishes. Their space is then
        // removed in one step, animating the panel and remaining rows together.
        for (let i = 0; i < toastModel.count; ++i) {
            if (!next[toastModel.get(i).toastId]) {
                const row = toastRepeater.itemAt(i);
                if (row)
                    row.beginDismiss(false);
            }
        }

        for (let i = 0; i < toasts.length; ++i) {
            const toast = toasts[i];
            const key = String(toast.id);
            const existing = indexOfToast(key);
            if (existing < 0) {
                toastModel.insert(i, { toastId: key, toast: toast });
            } else {
                if (existing !== i)
                    toastModel.move(existing, i, 1);
                if (previousToasts[key] !== toast) {
                    toastModel.setProperty(i, "toast", toast);
                    const row = toastRepeater.itemAt(i);
                    if (row)
                        row.cancelDismiss();
                }
            }
        }
        previousToasts = next;
        Qt.callLater(updateReveal);
    }

    function finishDismiss(id, removeNotification) {
        if (removeNotification)
            NotificationManager.removeToast(id);
        const index = indexOfToast(id);
        if (index >= 0)
            toastModel.remove(index);
        updateReveal();
    }

    function syncWindows() {
        if (panelMotion.active) {
            blurBackdrop.visible = true;
            root.visible = true;
        } else {
            root.visible = false;
            blurBackdrop.visible = false;
        }
    }

    onToastsChanged: {
        syncToasts();
        if (toasts.length > 0 && !OsdService.overlayVisible)
            expiryTimer.restart();
    }
    onShouldShowChanged: {
        Qt.callLater(updateReveal);
    }
    Component.onCompleted: {
        syncToasts();
        syncWindows();
    }

    PopupMotion {
        id: panelMotion
        opened: root.panelOpened
        distance: sharedPanel.height
        onActiveChanged: root.syncWindows()
    }

    visible: false
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:notifications"
    focusable: false
    color: "transparent"

    anchors { top: true; right: true }
    margins.top: OverlayService.topMargin(root.screen)
    implicitWidth: sharedPanel.width
    // Keep the Wayland surface and swapchain fixed while the panel animates.
    // Per-frame resizing reallocates render buffers and waits on the compositor.
    implicitHeight: Math.max(1, (screen ? screen.height : 1080) - margins.top)
    mask: PopupRegion { surfaceItem: sharedPanel; motion: panelMotion }

    function dismissOne(toast, card) {
        if (!toast)
            return;
        if (card)
            card.beginDismiss(true);
        else
            NotificationManager.removeToast(toast.id);
    }

    // The oldest card expires first, so a burst drains from the bottom and the
    // stack shrinks smoothly instead of vanishing all at once.
    Timer {
        id: expiryTimer
        interval: Config.toastDurationMs
        running: root.toasts.length > 0 && !OsdService.overlayVisible
        repeat: true
        onTriggered: {
            if (root.toasts.length > 0) {
                const toast = root.toasts[root.toasts.length - 1];
                root.dismissOne(toast, toastRepeater.itemAt(root.indexOfToast(toast.id)));
            }
        }
    }

    PanelWindow {
        id: blurBackdrop
        visible: false
        screen: root.screen
        anchors { top: true; right: true }
        margins.top: root.margins.top
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:popup-backdrop"
        focusable: false
        color: "transparent"
        mask: Region {}
        implicitWidth: root.width
        implicitHeight: root.height

        AttachedGlass {
            screen: root.screen
            sourceWindow: blurBackdrop
            joinProgress: panelMotion.joinProgress
            revealProgress: panelMotion.expansionProgress
            active: panelMotion.active
            width: sharedPanel.width
            height: sharedPanel.height
            flowProgress: panelMotion.progress
            color: Theme.barBackground
            cornerRadius: sharedPanel.cornerRadius
            transform: [
                Translate { y: panelMotion.offsetY },
                Scale {
                    origin.x: sharedPanel.width
                    origin.y: 0
                    xScale: panelMotion.scaleX
                    yScale: panelMotion.scaleY
                }
            ]
        }
    }

    Item {
        id: sharedPanel
        readonly property real cornerRadius: 20
        readonly property real revealedHeight: Math.min(height, 3 * cornerRadius) * panelMotion.joinProgress
            + Math.max(0, height - 3 * cornerRadius) * panelMotion.expansionProgress
        anchors.top: parent.top
        anchors.right: parent.right
        width: 360 + cornerRadius
        height: stack.implicitHeight + cornerRadius
        transform: [
            Translate { y: panelMotion.offsetY },
            Scale {
                origin.x: sharedPanel.width
                origin.y: 0
                xScale: panelMotion.scaleX
                yScale: panelMotion.scaleY
            }
        ]

        Behavior on height {
            enabled: panelMotion.progress > 0 && root.shouldShow
            NumberAnimation { duration: root.motionDuration; easing.type: Easing.OutCubic }
        }

        // Clip only the rows; text and icons stay in the main scene graph.
        // The curved background no longer captures and redraws the entire list.
        Item {
            width: parent.width
            height: Math.max(0, sharedPanel.revealedHeight
                - sharedPanel.cornerRadius * panelMotion.joinProgress)
            opacity: panelMotion.contentOpacity
            clip: true

            Column {
                id: stack
                width: parent.width

                move: Transition {
                    NumberAnimation {
                        property: "y"
                        duration: root.motionDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Repeater {
                    id: toastRepeater
                    model: toastModel

                    delegate: Item {
                        id: toastCard

                        required property int index
                        required property string toastId
                        required property var toast
                        property bool dismissing: false
                        property bool removeNotification: false
                        property bool rowOpened: false

                        Component.onCompleted: Qt.callLater(function() {
                            if (!dismissing)
                                rowOpened = true;
                        })

                        function beginDismiss(removeFromQueue) {
                            if (dismissing)
                                return;
                            removeNotification = removeFromQueue;
                            dismissing = true;
                            rowOpened = false;
                            root.updateReveal();
                            // A notification can be withdrawn before its first
                            // frame. It still needs to leave the retained model.
                            if (!rowMotion.active)
                                Qt.callLater(function() {
                                    if (toastCard.dismissing)
                                        root.finishDismiss(toastCard.toastId, toastCard.removeNotification);
                                });
                        }

                        function cancelDismiss() {
                            dismissing = false;
                            removeNotification = false;
                            rowOpened = true;
                        }

                        width: stack.width
                        // Rows contribute content height only; the shared panel owns
                        // the one bottom corner and the continuous background.
                        readonly property real cardHeight: 24 + Math.max(42, toastText.implicitHeight)
                        height: cardHeight

                        enabled: !dismissing
                        transform: [
                            Translate { x: (1 - rowMotion.progress) * toastCard.width },
                            Scale {
                                origin.x: toastCard.width
                                origin.y: toastCard.height / 2
                                xScale: rowMotion.scaleX
                                yScale: rowMotion.scaleY
                            }
                        ]
                        PopupMotion {
                            id: rowMotion
                            expandFromBar: false
                            opened: toastCard.rowOpened
                            onClosed: if (toastCard.dismissing)
                                root.finishDismiss(toastCard.toastId, toastCard.removeNotification)
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: sharedPanel.cornerRadius + 14
                            anchors.rightMargin: 17
                            height: 1
                            color: Theme.popupSurface1
                            visible: toastCard.index > 0
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 12
                            anchors.leftMargin: 14 + sharedPanel.cornerRadius
                            anchors.rightMargin: 17
                            height: toastCard.cardHeight - 24
                            spacing: 11

                            ClippingRectangle {
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 42
                                radius: Theme.radius
                                color: Theme.popupSurface0

                                // Prefer the protocol-provided notification image. It is
                                // commonly a sender/contact avatar; the app icon remains
                                // underneath as a universal fallback.
                                //
                                // A plain Image is used because root.iconSource() has
                                // already resolved the name to a URL: passing a bare
                                // name to IconImage would be read as a relative path.
                                Image {
                                    id: toastIcon

                                    anchors.fill: parent
                                    anchors.margins: 7
                                    source: root.iconSource(
                                        NotificationManager.primaryAppIcon(toastCard.toast))
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                    visible: !toastPhoto.visible
                                            && source.toString().length > 0
                                            && status === Image.Ready
                                }

                                Image {
                                    id: toastPhoto

                                    anchors.fill: parent
                                    anchors.margins: -6
                                    source: NotificationManager.primaryImage(toastCard.toast)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: source.toString().length > 0
                                            && status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "notifications"
                                    visible: !toastIcon.visible && !toastPhoto.visible
                                    color: Theme.colors.mauve
                                    font.family: Theme.iconFamily
                                    font.pixelSize: 21
                                }
                            }

                            ColumnLayout {
                                id: toastText
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    font.family: Theme.textFamily
                                    Layout.fillWidth: true
                                    text: toastCard.toast.summary
                                    color: Theme.colors.text
                                    font.pixelSize: 13
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    font.family: Theme.textFamily
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: toastCard.toast.body
                                    textFormat: Text.PlainText
                                    color: Theme.colors.textDim
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                text: "close"
                                color: Theme.colors.textDim
                                font.family: Theme.iconFamily
                                font.pixelSize: 18

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.dismissOne(toastCard.toast, toastCard)
                                }
                            }
                        }

                        // Clicking the card body dismisses it as well.
                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: 34
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismissOne(toastCard.toast, toastCard)
                        }
                    }
                }
            }
        }
    }
}
