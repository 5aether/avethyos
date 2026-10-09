import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "../components"
import "../widgets"

RowLayout {
    id: root

    function togglePopup(): void {
        NowPlayingService.setPopupOpen(!NowPlayingService.popupOpen);
    }

    function syncPopupWindows() {
        // Explicit mapping order keeps the blur behind the foreground.
        if (popupMotion.active || NowPlayingService.popupMapped) {
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
    }

    Binding {
        target: NowPlayingService
        property: "barHidden"
        value: OverlayService.topMargin(root.QsWindow.window?.screen ?? null) === 0
    }

    IpcHandler {
        target: "mediaplayer"
        function toggle(): void { root.togglePopup(); }
    }

    PopupFocus {
        popupWindow: popup
        opened: NowPlayingService.popupOpen
        dismissAction: function() { NowPlayingService.setPopupOpen(false); }
    }

    PopupMotion {
        id: popupMotion
        opened: NowPlayingService.popupOpen
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
    property color popupTextColor: coverColor.length > 0 ? coverColor : Theme.colors.text
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
        NowPlayingService.barView = barTrack;
        NowPlayingService.popupView = popupTrack;
        requestCoverColor();
        syncPopupWindows();
    }
    Component.onDestruction: {
        if (NowPlayingService.barView === barTrack)
            NowPlayingService.barView = null;
        if (NowPlayingService.popupView === popupTrack)
            NowPlayingService.popupView = null;
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
        opacity: NowPlayingService.ownsView("bar") ? 1 : 0
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
        visible: NowPlayingService.popupOpen
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

        AttachedPanel {
            x: popupFrame.x
            width: popupFrame.width
            height: popupFrame.height
            flowProgress: popupMotion.progress
            flowStrength: 0.075
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
        readonly property int shadowPadding: 40
        readonly property int cornerRadius: 20
        readonly property int coverBlendHeight: 36
        visible: false
        screen: root.QsWindow.window?.screen ?? null
        anchors { top: true; right: true }
        margins.top: OverlayService.topMargin(screen)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:mediaplayer"
        focusable: NowPlayingService.popupOpen
        onVisibleChanged: {
            if (visible)
                root.syncPosition();
        }
        implicitWidth: 520 + cornerRadius + shadowPadding
        implicitHeight: 226 + cornerRadius + shadowPadding
        mask: Region { item: popupFrame }
        color: "transparent"

        // Cast shadows from the rounded silhouette so artwork and controls
        // never contribute outlines. Extra window padding keeps the blur intact.
        MediaPopupShape {
            id: popupShadowSource
            anchors.fill: popupFrame
            visible: false
        }

        // The card joins the bar at its top edge. Keep the shadow below that
        // seam so it cannot draw a second rounded edge across the bar.
        Item {
            id: popupShadowLayer
            visible: popupMotion.active
            transform: [
                Translate { y: popupMotion.offsetY },
                Scale {
                    origin.x: popupShadowLayer.width
                    origin.y: 0
                    xScale: popupMotion.scaleX
                    yScale: popupMotion.scaleY
                }
            ]
            y: popupFrame.y
            width: parent.width
            height: parent.height - y
            clip: true
            // An interior shadow would darken the translucent join with the bar.
            layer.enabled: true
            layer.smooth: true
            layer.effect: OpacityMask {
                invert: true
                maskSource: Item {
                    width: popupShadowLayer.width
                    height: popupShadowLayer.height

                    MediaPopupShape {
                        // Clear the antialiased fringe too: overlapping shadow
                        // alpha can make compositor blur expose a bright rim.
                        x: popupFrame.x - 2
                        width: popupFrame.width + 2
                        height: popupFrame.height + 2
                    }
                }
            }

            MultiEffect {
                x: popupFrame.x
                width: popupFrame.width
                height: popupFrame.height
                source: popupShadowSource
                shadowEnabled: true
                shadowVerticalOffset: 3
                shadowBlur: 0.8
                shadowOpacity: 0.28
                shadowColor: "black"
                blurMax: 32
            }
        }

        Item {
            id: popupFrame
            visible: popupMotion.active
            enabled: NowPlayingService.popupOpen
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
            x: popup.shadowPadding
            y: 0
            width: popup.width - popup.shadowPadding
            height: popup.height - popup.shadowPadding

            AttachedPanel {
                anchors.fill: parent
                flowProgress: popupMotion.progress
                flowStrength: 0.075
                color: "transparent"
                cornerRadius: popupFrame.cornerRadius
                edgeSoftness: popupFrame.edgeSoftness
                MediaBackdrop {
                    anchors.fill: parent
                    artUrl: root.artUrl
                    blendHeight: popup.coverBlendHeight
                }
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

            MediaTrackView {
                id: popupTrack
                // The carrier captures a fixed destination. Keep this view in
                // the window's coordinates while the shell bubbles around it.
                parent: popup.contentItem
                mode: "popup"
                x: popupFrame.x + popupContent.x
                y: popupFrame.y + popupContent.y
                width: popupContent.width
                height: popupContent.height
                textTop: popupTextSlot.y
                titleColor: root.popupTextColor
                artistColor: root.popupTextColor
                opacity: NowPlayingService.ownsView("popup") ? 1 : 0
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

    // Shadow and cutout follow the visible panel's rounder silhouette.
    component MediaPopupShape: Shape {
        id: contour
        property color fillColor: "black"
        readonly property real cornerRadius: popup.cornerRadius
        readonly property real bodyLeft: cornerRadius
        readonly property real bodyBottom: height - cornerRadius

        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true
        layer.smooth: true
        // The blur consumes a fixed native-size texture; supersampling the
        // shadow only increases allocation and first-open rendering cost.
        layer.textureSize: Qt.size(Math.ceil(width), Math.ceil(height))

        ShapePath {
            fillColor: contour.fillColor
            strokeWidth: 0
            startX: 0
            startY: 0
            PathArc { x: contour.bodyLeft; y: contour.cornerRadius; radiusX: contour.cornerRadius; radiusY: contour.cornerRadius; direction: PathArc.Clockwise }
            PathLine { x: contour.bodyLeft; y: contour.bodyBottom - contour.cornerRadius }
            PathArc { x: contour.bodyLeft + contour.cornerRadius; y: contour.bodyBottom; radiusX: contour.cornerRadius; radiusY: contour.cornerRadius; direction: PathArc.Counterclockwise }
            PathLine { x: contour.width - contour.cornerRadius; y: contour.bodyBottom }
            PathArc { x: contour.width; y: contour.height; radiusX: contour.cornerRadius; radiusY: contour.cornerRadius; direction: PathArc.Clockwise }
            PathLine { x: contour.width; y: 0 }
            PathLine { x: 0; y: 0 }
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
        color: buttonMouse.containsMouse
               ? (primary ? Theme.colors.mauve : Theme.colors.surface2)
               : (primary ? Qt.lighter(Theme.colors.surface1, 1.2) : Theme.colors.surface0)

        Text {
            id: buttonText
            anchors.centerIn: parent
            text: button.label
            color: root.popupTextColor
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
