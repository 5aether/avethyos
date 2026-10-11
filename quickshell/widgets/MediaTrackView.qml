import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import "../components"

// Both song cards stay alive throughout a swipe. Only scene-graph positions
// change, so artwork loading and text layout never interrupt the motion.
Item {
    id: root

    property string mode: "bar"
    // The carrier reads animation bounds without changing the fixed endpoint
    // geometry used by captures and track layouts.
    property var panelMotion: null
    property var panelSurface: null
    property real revealBottom: root.QsWindow.window?.height ?? root.height
    property bool followsOwnership: true
    property var displayedTrack: ({ key: "", title: "", artist: "", artUrl: "", album: "", playerName: "" })
    property color titleColor: Theme.colors.text
    property color artistColor: Theme.colors.textDim
    property real coverSize: mode === "popup" ? 164 : mode === "toast" ? 42 : 32
    property real coverRadius: Theme.radius
    property real spacing: mode === "popup" ? 18 : mode === "toast" ? 11 : 8
    property real coverTop: (height - coverSize) / 2
    property real textTop: (height - metadataHeight) / 2

    readonly property bool animating: motionPhase !== "idle"
    readonly property real textWidth: Math.max(0, width - coverSize - spacing)
    readonly property real metadataHeight: activeCard.metadataHeight
    property alias coverItem: anchorsForCapture.coverItem
    property alias titleItem: anchorsForCapture.titleItem
    property alias artistItem: anchorsForCapture.artistItem

    property var targetTrack: null
    property string motionPhase: "idle"
    property real slideProgress: 0
    property var trackHistory: []
    property int historyIndex: -1
    property int swipeDirection: 1
    readonly property int swipeDuration: mode === "toast" ? 420 : 300
    property int activeBuffer: 0
    readonly property TrackCard activeCard: activeBuffer === 0 ? firstCard : secondCard
    readonly property TrackCard nextCard: activeBuffer === 0 ? secondCard : firstCard
    readonly property real swipeDistance: Math.max(1, width) + spacing
    readonly property bool presentationVisible: root.visible && root.opacity > 0.98
        && (!followsOwnership || NowPlayingService.ownsView(root.mode))

    implicitWidth: mode === "bar"
        ? coverSize + spacing + Math.min(170, Math.ceil(Math.max(titleItem.implicitWidth, artistItem.implicitWidth)))
        : mode === "toast" ? 288 : 484
    implicitHeight: mode === "popup" ? 190 : mode === "toast" ? 58 : 32
    clip: true

    QtObject {
        id: anchorsForCapture
        readonly property Item coverItem: root.activeCard.coverItem
        readonly property Item titleItem: root.activeCard.titleItem
        readonly property Item artistItem: root.activeCard.artistItem
    }

    function snapshot(track) {
        return {
            key: String(track?.key ?? ""),
            historyKey: String(track?.historyKey ?? ""),
            title: String(track?.title ?? ""),
            artist: String(track?.artist ?? ""),
            artUrl: String(track?.artUrl ?? ""),
            album: String(track?.album ?? ""),
            playerName: String(track?.playerName ?? "")
        };
    }

    function sameTrack(left, right) {
        if (!left || !right)
            return false;
        if (left.key || right.key)
            return left.key === right.key;
        return left.title === right.title && left.artist === right.artist
            && left.album === right.album;
    }

    function hasTrack(track) {
        return track && (track.key || track.title || track.artist);
    }

    function sameHistoryTrack(left, right) {
        return sameTrack(left, right)
            || !!left?.historyKey && left.historyKey === right?.historyKey;
    }

    function directionForTrack(track) {
        const index = trackHistory.findIndex(previous => sameHistoryTrack(previous, track));
        return index >= 0 && index < historyIndex ? -1 : 1;
    }

    function rememberTrack(track) {
        if (!hasTrack(track)) {
            trackHistory = [];
            historyIndex = -1;
            return;
        }
        const index = trackHistory.findIndex(previous => sameHistoryTrack(previous, track));
        if (index >= 0) {
            trackHistory = trackHistory.map((previous, position) =>
                position === index ? snapshot(track) : previous);
            historyIndex = index;
        } else {
            trackHistory = trackHistory.slice(0, historyIndex + 1)
                .concat([snapshot(track)]).slice(-64);
            historyIndex = trackHistory.length - 1;
        }
    }

    function setTrack(track, animate) {
        targetTrack = snapshot(track);
        if (!animate || !hasTrack(displayedTrack) || !hasTrack(targetTrack)) {
            settle();
            return;
        }
        // Freeze both moving cards. Rapid skips coalesce into one subsequent
        // swipe instead of replacing artwork halfway across the viewport.
        if (motionPhase !== "idle")
            return;
        if (sameTrack(displayedTrack, targetTrack)) {
            displayedTrack = targetTrack;
            activeCard.track = targetTrack;
            rememberTrack(displayedTrack);
            return;
        }
        exitTrack();
    }

    function exitTrack() {
        if (motionPhase !== "idle" || sameTrack(displayedTrack, targetTrack))
            return;
        motionPhase = "preload";
        swipeDirection = directionForTrack(targetTrack);
        activeCard.restartScroll();
        nextCard.track = snapshot(targetTrack);
        nextCard.artworkVisible = false;
        activeCard.place(0);
        nextCard.place(swipeDirection);
        preloadTimeout.restart();
        Qt.callLater(prepareSwipe);
    }

    function prepareSwipe() {
        if (motionPhase === "preload" && nextCard.coverStatus !== Image.Loading)
            swipeReady.restart();
    }

    function startSwipe() {
        if (motionPhase !== "preload")
            return;
        preloadTimeout.stop();
        swipeReady.stop();
        nextCard.artworkVisible = nextCard.coverStatus === Image.Ready;
        motionPhase = "swipe";
        swipe.start();
    }

    function finishSwipe() {
        activeBuffer = 1 - activeBuffer;
        displayedTrack = activeCard.track;
        activeCard.place(0);
        nextCard.place(1);
        motionPhase = "idle";
        if (sameTrack(displayedTrack, targetTrack)) {
            displayedTrack = targetTrack;
            activeCard.track = targetTrack;
        }
        rememberTrack(displayedTrack);
        activeCard.artworkVisible = activeCard.coverStatus === Image.Ready;
        activeCard.restartScroll();
        Qt.callLater(exitTrack);
    }

    function settle() {
        preloadTimeout.stop();
        swipeReady.stop();
        swipe.stop();
        motionPhase = "idle";
        if (targetTrack !== null) {
            displayedTrack = targetTrack;
            activeCard.track = targetTrack;
        }
        rememberTrack(displayedTrack);
        activeCard.place(0);
        nextCard.place(1);
        activeCard.artworkVisible = activeCard.coverStatus === Image.Ready;
        slideProgress = 0;
        activeCard.restartScroll();
    }

    function capture() {
        const window = root.QsWindow.window;
        if (!window || !window.screen || !window.contentItem)
            return null;
        const screen = window.screen;
        // Layer surfaces use panel anchors for their screen-space position.
        const originX = window.anchors?.right && !window.anchors?.left
            ? screen.width - window.width - (window.margins?.right ?? 0)
            : (window.margins?.left ?? 0);
        const originY = window.margins?.top ?? 0;
        function geometry(item) {
            const point = window.contentItem.mapFromItem(item, 0, 0);
            return { x: originX + point.x, y: originY + point.y,
                     width: item.width, height: item.height };
        }
        const coverGeometry = geometry(coverItem);
        coverGeometry.radius = coverItem.radius;
        const titleGeometry = geometry(activeCard.titleViewportItem);
        titleGeometry.fontSize = titleItem.font.pixelSize;
        titleGeometry.color = titleItem.color;
        titleGeometry.bold = titleItem.font.bold;
        const artistGeometry = geometry(artistItem);
        artistGeometry.fontSize = artistItem.font.pixelSize;
        artistGeometry.color = artistItem.color;
        artistGeometry.bold = artistItem.font.bold;
        return { track: snapshot(displayedTrack), cover: coverGeometry,
                 title: titleGeometry, artist: artistGeometry,
                 bounds: geometry(root), screen: screen };
    }

    // Allow a frame for texture upload. A slow cover cannot hold up the swipe.
    Timer {
        id: swipeReady
        interval: 16
        onTriggered: root.startSwipe()
    }
    Timer {
        id: preloadTimeout
        interval: 180
        onTriggered: root.startSwipe()
    }

    component TrackCard: Item {
        id: card
        property var track: ({ key: "", title: "", artist: "", artUrl: "", album: "", playerName: "" })
        property bool artworkVisible: false
        readonly property bool current: root.activeCard === card
        readonly property int coverStatus: coverImage.status
        readonly property real metadataHeight: metadata.height
        property alias contentItem: content
        property alias coverItem: cover
        property alias metadataItem: metadata
        property alias titleItem: titleText
        property alias titleViewportItem: titleViewport
        property alias artistItem: artistText
        width: root.width
        height: root.height
        visible: current || root.motionPhase !== "idle"

        function place(position) {
            content.x = root.mode === "popup" ? 0 : position * root.swipeDistance;
            cover.x = root.mode === "popup" ? position * (root.coverSize + root.spacing) : 0;
            metadata.x = root.mode === "popup" ? position * (root.textWidth + root.spacing) : 0;
        }

        function restartScroll() {
            titleViewport.restartScroll();
        }

        Item {
            id: content
            width: card.width
            height: card.height

            // Each popup lane clips independently, away from the controls.
            Item {
                width: root.coverSize
                height: root.height
                clip: root.mode === "popup"

                ClippingRectangle {
                    id: cover
                    y: root.coverTop
                    width: root.coverSize
                    height: width
                    radius: root.coverRadius
                    contentInsideBorder: false
                    color: Theme.colors.surface0

                    Image {
                        id: coverImage
                        anchors.fill: parent
                        source: card.track?.artUrl ?? ""
                        sourceSize: Qt.size(Math.ceil(root.coverSize * (root.QsWindow.window?.devicePixelRatio ?? 1)),
                            Math.ceil(root.coverSize * (root.QsWindow.window?.devicePixelRatio ?? 1)))
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                        visible: card.artworkVisible && status === Image.Ready
                        onStatusChanged: {
                            if (root.motionPhase === "idle" && card.current)
                                card.artworkVisible = status === Image.Ready;
                            if (root.motionPhase === "preload" && !card.current)
                                root.prepareSwipe();
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "music_note"
                        color: root.artistColor
                        font.family: Theme.iconFamily
                        font.pixelSize: Math.min(34, Math.max(16, root.coverSize * 0.5))
                        visible: !coverImage.visible
                    }
                }
            }

            Item {
                x: root.coverSize + root.spacing
                width: root.textWidth
                height: root.height
                clip: root.mode === "popup"

                Column {
                    id: metadata
                    y: root.textTop
                    width: root.textWidth
                    spacing: root.mode === "bar" ? 0 : 2

                    Text {
                        visible: root.mode === "toast"
                        width: parent.width
                        text: "NOW PLAYING"
                        color: root.artistColor
                        font.family: Theme.textFamily
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1
                        elide: Text.ElideRight
                    }

                    Item {
                        id: titleViewport
                        width: parent.width
                        height: titleText.implicitHeight
                        clip: true

                        readonly property bool scrolling: root.mode === "bar"
                            && OverlayService.topMargin(root.QsWindow.window?.screen ?? null) > 0
                            && titleText.implicitWidth > width && width > 0
                        readonly property bool scrollActive: scrolling && card.current
                            && root.presentationVisible && !root.animating
                        readonly property real scrollDistance: titleText.width + titleStrip.spacing
                        readonly property real fadeStop: Math.min(0.5, 12 / Math.max(1, width))

                        layer.enabled: scrolling
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: titleViewport.width
                                height: titleViewport.height
                                visible: false
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: titleViewport.fadeStop; color: "black" }
                                    GradientStop { position: 1 - titleViewport.fadeStop; color: "black" }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                            }
                        }

                        function restartScroll() {
                            titleScroll.stop();
                            titleStrip.x = 0;
                            if (scrollActive)
                                titleScroll.start();
                        }

                        onScrollActiveChanged: Qt.callLater(restartScroll)
                        onWidthChanged: Qt.callLater(restartScroll)

                        Row {
                            id: titleStrip
                            spacing: 32

                            Text {
                                id: titleText
                                width: titleViewport.scrolling
                                    ? Math.max(implicitWidth, titleViewport.width) : titleViewport.width
                                text: card.track?.title || "Unknown track"
                                color: root.titleColor
                                font.family: Theme.textFamily
                                font.pixelSize: root.mode === "popup" ? 16 : root.mode === "toast" ? 14 : 11
                                font.bold: true
                                elide: titleViewport.scrolling ? Text.ElideNone : Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                                onTextChanged: Qt.callLater(titleViewport.restartScroll)
                                onImplicitWidthChanged: Qt.callLater(titleViewport.restartScroll)
                            }

                            Text {
                                visible: titleViewport.scrolling
                                text: titleText.text
                                font: titleText.font
                                color: titleText.color
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        SequentialAnimation {
                            id: titleScroll
                            loops: Animation.Infinite
                            PropertyAction { target: titleStrip; property: "x"; value: 0 }
                            PauseAnimation { duration: 1200 }
                            XAnimator {
                                target: titleStrip
                                from: 0
                                to: -titleViewport.scrollDistance
                                duration: Math.round(titleViewport.scrollDistance / 30 * 1000)
                                easing.type: Easing.Linear
                            }
                        }
                    }

                    Text {
                        id: artistText
                        width: parent.width
                        text: card.track?.artist || card.track?.playerName || "Unknown artist"
                        color: root.artistColor
                        font.family: Theme.textFamily
                        font.pixelSize: root.mode === "popup" ? 13 : root.mode === "toast" ? 11 : 10
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                        width: parent.width
                        visible: root.mode === "popup" && text.length > 0
                        text: card.track?.album ?? ""
                        color: root.artistColor
                        font.family: Theme.textFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    TrackCard { id: firstCard }
    TrackCard { id: secondCard }

    ParallelAnimation {
        id: swipe
        XAnimator {
            target: root.activeCard.contentItem
            from: 0
            to: root.mode === "popup" ? 0 : -root.swipeDirection * root.swipeDistance
            duration: root.swipeDuration
            easing.type: root.mode === "toast" ? Easing.InOutCubic : Easing.OutCubic
        }
        XAnimator {
            target: root.nextCard.contentItem
            from: root.mode === "popup" ? 0 : root.swipeDirection * root.swipeDistance
            to: 0
            duration: root.swipeDuration
            easing.type: root.mode === "toast" ? Easing.InOutCubic : Easing.OutCubic
        }
        XAnimator {
            target: root.activeCard.coverItem
            from: 0
            to: root.mode === "popup" ? -root.swipeDirection * (root.coverSize + root.spacing) : 0
            duration: root.swipeDuration
            easing.type: root.mode === "toast" ? Easing.InOutCubic : Easing.OutCubic
        }
        XAnimator {
            target: root.nextCard.coverItem
            from: root.mode === "popup" ? root.swipeDirection * (root.coverSize + root.spacing) : 0
            to: 0
            duration: root.swipeDuration
            easing.type: root.mode === "toast" ? Easing.InOutCubic : Easing.OutCubic
        }
        XAnimator {
            target: root.activeCard.metadataItem
            from: 0
            to: root.mode === "popup" ? -root.swipeDirection * (root.textWidth + root.spacing) : 0
            duration: root.swipeDuration
            easing.type: root.mode === "toast" ? Easing.InOutCubic : Easing.OutCubic
        }
        XAnimator {
            target: root.nextCard.metadataItem
            from: root.mode === "popup" ? root.swipeDirection * (root.textWidth + root.spacing) : 0
            to: 0
            duration: root.swipeDuration
            easing.type: root.mode === "toast" ? Easing.InOutCubic : Easing.OutCubic
        }
        onFinished: root.finishSwipe()
    }
}
