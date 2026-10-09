import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components"
import "../widgets"

// Fullscreen has no visible bar endpoint. Present the toast with bubble motion
// there, and keep the shared song endpoints still during a visible-bar handoff.
PanelWindow {
    id: root

    readonly property bool showing: NowPlayingService.toastMapped
    readonly property bool shouldShow: showing && !OsdService.overlayVisible
    readonly property int coverBlendHeight: NowPlayingService.barHidden ? 0 : 36
    readonly property bool standalonePresentation: NowPlayingService.toastStandalone || NowPlayingService.barHidden

    function syncWindows() {
        if (popupMotion.active || shouldShow && NowPlayingService.moving) {
            blurBackdrop.visible = popupMotion.active && !NowPlayingService.barHidden;
            root.visible = true;
        } else {
            root.visible = false;
            blurBackdrop.visible = false;
        }
    }

    PopupMotion {
        id: popupMotion
        opened: root.shouldShow && !NowPlayingService.toastClosing
            && (NowPlayingService.ownsView("toast")
                || NowPlayingService.moving && NowPlayingService.transferTo === "toast")
        distance: toastCard.height
        onActiveChanged: root.syncWindows()
        onClosed: {
            if (NowPlayingService.toastClosing)
                NowPlayingService.finishToastExit();
        }
    }
    Component.onCompleted: {
        NowPlayingService.toastView = toastTrack;
        syncWindows();
    }
    Component.onDestruction: {
        if (NowPlayingService.toastView === toastTrack)
            NowPlayingService.toastView = null;
    }
    onShouldShowChanged: syncWindows()
    visible: false
    screen: NowPlayingService.barView?.QsWindow.window?.screen ?? null
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:nowplaying"
    focusable: false
    color: "transparent"
    mask: Region {}

    anchors { top: true; right: true }
    margins.top: NowPlayingService.barHidden ? 0 : Theme.barHeight
    implicitWidth: toastCard.width
    implicitHeight: toastCard.height + 24

    Connections {
        target: NowPlayingService
        function onToastClosingChanged() {
            if (NowPlayingService.toastClosing && !popupMotion.active)
                NowPlayingService.finishToastExit();
        }
        function onBarHiddenChanged() { root.syncWindows(); }
        function onMovingChanged() { root.syncWindows(); }
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

        AttachedPanel {
            width: toastCard.width
            height: toastCard.height
            flowProgress: popupMotion.progress
            flowStrength: 0.075
            color: Theme.barBackground
            cornerRadius: toastCard.cornerRadius
            transform: [
                Translate { y: popupMotion.offsetY },
                Scale {
                    origin.x: toastCard.width
                    origin.y: 0
                    xScale: popupMotion.scaleX
                    yScale: popupMotion.scaleY
                }
            ]
        }
    }

    Item {
        id: toastCard
        x: root.width - width
        width: 380
        height: 102
        readonly property real cornerRadius: 20
        transform: [
            Translate { y: popupMotion.offsetY },
            Scale {
                origin.x: toastCard.width
                origin.y: 0
                xScale: popupMotion.scaleX
                yScale: popupMotion.scaleY
            }
        ]

        // Mask the artwork background while the shared song view moves freely.
        AttachedPanel {
            anchors.fill: parent
            flowProgress: popupMotion.progress
            flowStrength: 0.075
            color: NowPlayingService.barHidden ? Theme.colors.surface0 : "transparent"
            cornerRadius: toastCard.cornerRadius
            MediaBackdrop {
                anchors.fill: parent
                artUrl: toastTrack.displayedTrack.artUrl || ""
                blendHeight: root.coverBlendHeight
            }
        }

        MediaTrackView {
            id: toastTrack
            // The shared-element carrier captures a fixed endpoint while the
            // background scrolls into place. Standalone songs travel with it.
            parent: root.contentItem
            mode: "toast"
            x: 14 + toastCard.cornerRadius
            y: 12
            width: root.width - x - 17
            height: 58
            opacity: NowPlayingService.ownsView("toast") ? 1 : 0
            transform: [
                Translate {
                    y: root.standalonePresentation ? popupMotion.offsetY : 0
                },
                Scale {
                    origin.x: root.width - toastTrack.x
                    origin.y: -toastTrack.y
                    xScale: root.standalonePresentation ? popupMotion.scaleX : 1
                    yScale: root.standalonePresentation ? popupMotion.scaleY : 1
                }
            ]
        }
    }
}
