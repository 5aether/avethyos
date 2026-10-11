import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "../components"
import "../widgets"
import "../modules/mediaColors.js" as MediaColors

RowLayout {
    id: root

    readonly property var viewScreen: root.QsWindow.window?.screen ?? null
    readonly property bool activeEndpoint: NowPlayingService.barView === barTrack
    readonly property bool popupOpen: activeEndpoint && NowPlayingService.popupOpen
    property bool initialized: false

    onViewScreenChanged: if (initialized) NowPlayingService.registerViews(viewScreen, barTrack, popupTrack)

    function togglePopup(): void {
        if (popupOpen) {
            NowPlayingService.setPopupOpen(false);
        } else {
            NowPlayingService.activateScreen(viewScreen);
            NowPlayingService.setPopupOpen(true);
        }
    }

    function syncPopupWindows() {
        // Explicit mapping order keeps the blur behind the foreground.
        if (root.activeEndpoint && (popupMotion.active || NowPlayingService.popupMapped)) {
            popupBlurBackdrop.visible = popupMotion.active;
            popup.visible = true;
        } else {
            popup.visible = false;
            popupBlurBackdrop.visible = false;
        }
    }

    Connections {
        target: NowPlayingService
        function onPopupMappedChanged() { root.syncPopupWindows(); }
        function onBarViewChanged() { root.syncPopupWindows(); }
    }

    PopupFocus {
        popupWindow: popup
        opened: root.popupOpen
        dismissAction: function() { NowPlayingService.setPopupOpen(false); }
    }

    PopupMotion {
        id: popupMotion
        opened: root.popupOpen
        distance: popupFrame.height
        onActiveChanged: root.syncPopupWindows()
    }

    // The compact bar follows what is actually playing. The popup can select
    // another MPRIS source for inspection and control without replacing it.

    readonly property var player: MediaService.selectedPlayer
    readonly property string artUrl: popupTrack.displayedTrack.artUrl || ""
    property string coverColor: ""
    property string coverColorArtUrl: ""
    property string pendingColorArtUrl: ""
    property color popupTextColor: MediaColors.readableAccent(coverColor.length > 0 ? coverColor : Theme.colors.text)
    Behavior on popupTextColor { ColorAnimation { duration: 180 } }
    readonly property real lengthSeconds: Math.max(0, player?.length ?? 0)
    property real playbackPositionSeconds: 0
    property real seekPositionSeconds: 0
    property var seekPlayer: null
    readonly property real positionSeconds: seekMouse.pressed && seekPlayer !== null && seekPlayer === player
                                           ? seekPositionSeconds : playbackPositionSeconds
    readonly property bool playing: player?.isPlaying ?? false
    readonly property bool trackMovesWithShell: NowPlayingService.barHidden
        || !NowPlayingService.latestTrack.key.length

    function requestCoverColor(): void {
        const source = String(artUrl || "");
        if (!source.length) {
            pendingColorArtUrl = "";
            coverColor = "";
            coverColorArtUrl = "";
            return;
        }
        if (coverColorProcess.running) {
            pendingColorArtUrl = source;
            return;
        }
        coverColorProcess.sourceUrl = source;
        coverColorProcess.command = [
            "python3",
            Quickshell.shellPath("scripts/media-cover-color.py"),
            source
        ];
        coverColorProcess.running = true;
    }

    onArtUrlChanged: requestCoverColor()
    Component.onCompleted: {
        initialized = true;
        NowPlayingService.registerViews(viewScreen, barTrack, popupTrack);
        requestCoverColor();
        syncPopupWindows();
    }
    Component.onDestruction: {
        NowPlayingService.unregisterViews(barTrack);
    }

    Process {
        id: coverColorProcess
        property string sourceUrl: ""

        stdout: StdioCollector { id: coverColorOutput }

        onExited: function(exitCode) {
            const value = coverColorOutput.text.trim();
            if (exitCode === 0 && sourceUrl === root.artUrl
                    && /^#[0-9a-fA-F]{6}$/.test(value)) {
                root.coverColor = value;
                root.coverColorArtUrl = sourceUrl;
            } else if (sourceUrl === root.artUrl) {
                root.coverColor = "";
                root.coverColorArtUrl = "";
            }

            const next = root.pendingColorArtUrl;
            root.pendingColorArtUrl = "";
            if (next.length > 0 && next !== sourceUrl)
                Qt.callLater(root.requestCoverColor);
        }
    }

    function syncPosition() {
        const position = player && player.positionSupported ? player.position : 0;
        playbackPositionSeconds = isFinite(position)
            ? Math.max(0, lengthSeconds > 0 ? Math.min(position, lengthSeconds) : position) : 0;
    }

    onPlayerChanged: {
        seekPlayer = null;
        syncPosition();
    }

    Connections {
        target: root.player
        enabled: root.player !== null

        function onPositionChanged() {
            root.syncPosition();
        }

        function onPostTrackChanged() {
            root.seekPlayer = null;
            root.syncPosition();
        }

        function onPositionSupportedChanged() {
            root.syncPosition();
        }

        function onPlaybackStateChanged() {
            root.syncPosition();
        }

        function onRateChanged() {
            root.syncPosition();
        }

        function onLengthChanged() {
            root.syncPosition();
        }
    }

    // MPRIS calculates the current position when read, but does not notify on
    // every playback tick. Sample that local value while the popup is open.
    Timer {
        interval: 100
        repeat: true
        triggeredOnStart: true
        running: popup.visible && root.playing && (root.player?.positionSupported ?? false)
        onTriggered: root.syncPosition()
    }

    spacing: 8
    visible: NowPlayingService.latestTrack.key.length > 0
    // Retain the slot while its details travel; it remains clickable while
    // the toast owns the song details.
    Layout.preferredWidth: barTrack.implicitWidth
    Layout.preferredHeight: 32

    function formatDuration(seconds) {
        if (!isFinite(seconds) || seconds < 0) return "0:00";
        const rounded = Math.floor(seconds);
        const minutes = Math.floor(rounded / 60);
        const remainder = rounded % 60;
        return minutes + ":" + (remainder < 10 ? "0" : "") + remainder;
    }

    MediaTrackView {
        id: barTrack
        mode: "bar"
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: 32
        followsOwnership: root.activeEndpoint
        opacity: !root.activeEndpoint || NowPlayingService.ownsView("bar") ? 1 : 0
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: root.togglePopup()
    }

    // Invisible full-screen layer to catch clicks outside the popup
    PanelWindow {
        id: dismissLayer
        screen: popup.screen
        visible: root.popupOpen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:mediaplayer-dismiss"
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        MouseArea {
            anchors.fill: parent
            onPressed: mouse => {
                NowPlayingService.setPopupOpen(false);
                mouse.accepted = true;
            }
        }
    }

    // The translucent join uses compositor blur beneath the cover-art body.
    PanelWindow {
        id: popupBlurBackdrop
        visible: false
        screen: popup.screen
        anchors { top: true; right: true }
        margins.top: popup.margins.top
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        // Dedicated namespace keeps Hyprland from animating the glass join.
        WlrLayershell.namespace: "quickshell:popup-backdrop"
        color: "transparent"
        mask: Region {}
        implicitWidth: popup.width
        implicitHeight: popup.height

        AttachedGlass {
            screen: popup.screen
            sourceWindow: popupBlurBackdrop
            joinProgress: popupMotion.joinProgress
            revealProgress: popupMotion.expansionProgress
            active: popupMotion.active && root.activeEndpoint
            x: popupFrame.x
            width: popupFrame.width
            height: popupFrame.height
            flowProgress: popupMotion.progress
            transform: [
                Translate { y: popupMotion.offsetY },
                Scale {
                    origin.x: width
                    origin.y: 0
                    xScale: popupMotion.scaleX
                    yScale: popupMotion.scaleY
                }
            ]
            color: Theme.barBackground
            cornerRadius: popup.cornerRadius
            borderWidth: 0
            edgeSoftness: popupFrame.edgeSoftness
        }
    }

    PanelWindow {
        id: popup
        readonly property int cornerRadius: 20
        readonly property int coverBlendHeight: 36
        visible: false
        screen: root.QsWindow.window?.screen ?? null
        anchors { top: true; right: true }
        margins.top: OverlayService.topMargin(screen)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:mediaplayer"
        focusable: root.popupOpen
        onVisibleChanged: {
            if (visible)
                root.syncPosition();
        }
        implicitWidth: 520 + cornerRadius
        implicitHeight: 226 + cornerRadius
        mask: PopupRegion { surfaceItem: popupFrame; motion: popupMotion }
        color: "transparent"

        Item {
            id: popupTrackClip
            parent: popup.contentItem
            z: 1
            width: popup.width
            height: Math.max(0, popupSurface.revealedHeight - popupSurface.revealedRadius)
            clip: true
        }

        Item {
            id: popupFrame
            visible: popupMotion.active
            enabled: root.popupOpen
            transform: [
                Translate { y: popupMotion.offsetY },
                Scale {
                    origin.x: popupFrame.width
                    origin.y: 0
                    xScale: popupMotion.scaleX
                    yScale: popupMotion.scaleY
                }
            ]
            readonly property real cornerRadius: popup.cornerRadius
            readonly property real edgeSoftness: 2
            readonly property real revealedHeight: popupSurface.revealedHeight
            x: 0
            y: 0
            width: popup.width
            height: popup.height

            AttachedPanel {
                id: popupSurface
                anchors.fill: parent
                joinProgress: popupMotion.joinProgress
                revealProgress: popupMotion.expansionProgress
                contentOpacity: popupMotion.contentOpacity
                flowProgress: popupMotion.progress
                color: "transparent"
                cornerRadius: popupFrame.cornerRadius
                edgeSoftness: popupFrame.edgeSoftness
                MediaBackdrop {
                    anchors.fill: parent
                    artUrl: root.artUrl
                    blendHeight: popup.coverBlendHeight
                }
                RowLayout {
                    id: popupContent
                    anchors.fill: parent
                    anchors.margins: 18
                    // The shoulder extensions use the same radius as the card.
                    anchors.leftMargin: 18 + popupFrame.cornerRadius
                    anchors.bottomMargin: 18 + popupFrame.cornerRadius
                    spacing: 18

                    // Geometry stays stable while the shared song view travels.
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 164
                        Layout.preferredHeight: 164
                    }

                    // Right side: metadata and controls
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12

                        // Each MPRIS application is independently controllable.
                        // Opening the popup starts on the source shown in the bar;
                        // choosing another source only changes the popup.
                        ListView {
                            id: sourceList
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? 26 : 0
                            visible: count > 1
                            orientation: ListView.Horizontal
                            spacing: 6
                            clip: true
                            interactive: contentWidth > width
                            boundsBehavior: Flickable.StopAtBounds
                            model: MediaService.players

                            delegate: Rectangle {
                                id: sourceChip
                                required property var modelData

                                readonly property bool selected: modelData === root.player
                                width: Math.min(132, sourceName.implicitWidth + 20)
                                height: 26
                                radius: Theme.radius
                                color: selected ? Qt.rgba(0, 0, 0, 0.48)
                                                : Qt.rgba(0, 0, 0, 0.28)
                                border.width: selected ? 1 : 0
                                border.color: root.popupTextColor

                                Text {
                                    id: sourceName
                                    anchors.centerIn: parent
                                    width: Math.min(112, implicitWidth)
                                    text: (sourceChip.modelData.isPlaying ? "▶ " : "")
                                        + MediaService.playerName(sourceChip.modelData)
                                    color: root.popupTextColor
                                    font.family: Theme.textFamily
                                    font.pixelSize: 10
                                    font.bold: sourceChip.selected
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: MediaService.selectPlayer(sourceChip.modelData)
                                }
                            }
                        }

                        Item {
                            id: popupTextSlot
                            Layout.fillWidth: true
                            Layout.preferredHeight: popupTrack.displayedTrack.album ? 58 : 43
                        }

                        Item { Layout.fillHeight: true }

                        // Progress bar and time
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: Theme.radius
                                color: Qt.rgba(root.popupTextColor.r, root.popupTextColor.g,
                                               root.popupTextColor.b, 0.25)

                                Rectangle {
                                    width: root.lengthSeconds > 0
                                           ? Math.min(1, root.positionSeconds / root.lengthSeconds) * parent.width : 0
                                    height: parent.height
                                    radius: parent.radius
                                    color: root.popupTextColor
                                }

                                MouseArea {
                                    id: seekMouse
                                    anchors.fill: parent
                                    anchors.topMargin: -8
                                    anchors.bottomMargin: -8
                                    enabled: (root.player?.canSeek ?? false)
                                             && (root.player?.positionSupported ?? false)
                                             && root.lengthSeconds > 0
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: mouse => {
                                        root.seekPlayer = root.player;
                                        root.seekPositionSeconds = Math.max(0,
                                            Math.min(root.lengthSeconds, mouse.x / width * root.lengthSeconds));
                                    }
                                    onPositionChanged: mouse => {
                                        if (pressed) root.seekPositionSeconds = Math.max(0,
                                            Math.min(root.lengthSeconds, mouse.x / width * root.lengthSeconds));
                                    }
                                    onReleased: {
                                        if (root.player && root.player === root.seekPlayer
                                                && root.player.canSeek && root.player.positionSupported) {
                                            root.player.position = root.seekPositionSeconds;
                                            root.syncPosition();
                                        }
                                        root.seekPlayer = null;
                                    }
                                    onCanceled: {
                                        root.seekPlayer = null;
                                        root.syncPosition();
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    font.family: Theme.textFamily
                                    text: root.formatDuration(root.positionSeconds)
                                    color: root.popupTextColor
                                    font.pixelSize: 10
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    font.family: Theme.textFamily
                                    text: root.formatDuration(root.lengthSeconds)
                                    color: root.popupTextColor
                                    font.pixelSize: 10
                                }
                            }
                        }

                        // Control buttons
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Item { Layout.fillWidth: true }

                            MediaButton {
                                label: "skip_previous"
                                action: function() {
                                    if (root.player && root.player.canGoPrevious)
                                        root.player.previous()
                                }
                            }
                            MediaButton {
                                label: root.playing ? "pause" : "play_arrow"
                                action: function() {
                                    if (root.player && root.player.canTogglePlaying)
                                        root.player.togglePlaying()
                                }
                                primary: true
                            }
                            MediaButton {
                                label: "skip_next"
                                action: function() {
                                    if (root.player && root.player.canGoNext)
                                        root.player.next()
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }
                }

            }

            MediaTrackView {
                id: popupTrack
                // The carrier captures a fixed destination. Keep this view in
                // the window's coordinates while the shell bubbles around it.
                parent: popupTrackClip
                mode: "popup"
                panelMotion: popupMotion
                panelSurface: popupSurface
                revealBottom: popupSurface.revealedHeight - popupSurface.revealedRadius
                x: popupFrame.x + popupContent.x
                y: popupFrame.y + popupContent.y
                width: popupContent.width
                height: popupContent.height
                textTop: popupTextSlot.y
                titleColor: root.popupTextColor
                artistColor: root.popupTextColor
                opacity: NowPlayingService.ownsView("popup") ? popupMotion.contentOpacity : 0
                transform: [
                    Translate {
                        y: root.trackMovesWithShell ? popupMotion.offsetY : 0
                    },
                    Scale {
                        origin.x: popup.width - popupTrack.x
                        origin.y: -popupTrack.y
                        xScale: root.trackMovesWithShell ? popupMotion.scaleX : 1
                        yScale: root.trackMovesWithShell ? popupMotion.scaleY : 1
                    }
                ]
            }
        }

    }

    component MediaButton: Rectangle {
        id: button
        required property string label
        required property var action
        property bool primary: false

        implicitWidth: primary ? 80 : 64
        implicitHeight: primary ? 42 : 38
        width: implicitWidth
        height: implicitHeight
        radius: Theme.radius
        color: primary ? root.popupTextColor
            : Qt.rgba(0, 0, 0, buttonMouse.containsMouse ? 0.62 : 0.42)
        opacity: buttonMouse.containsMouse && primary ? 0.9 : 1

        Text {
            id: buttonText
            anchors.centerIn: parent
            text: button.label
            color: button.primary ? "#15121b" : root.popupTextColor
            font.family: Theme.iconFamily
            font.pixelSize: button.primary ? 28 : 22
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.action()
        }
    }
}
