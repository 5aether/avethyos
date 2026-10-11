import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../components"
import "../widgets"

// A temporary, input-transparent surface carries the song between windows.
// Its replacement scrolls in after the carried song reaches the destination.
PanelWindow {
    id: root

    property int activeSerial: -1
    property bool prepared: false
    property real progress: 0
    property var departure: null
    property var arrival: null
    property var track: null
    property var pendingFrame: null
    property int prepareAttempts: 0
    property bool awaitingStart: false
    property var layeredDestination: null
    property int flightDuration: NowPlayingService.transferDuration
    readonly property var destinationView: NowPlayingService.transferTo !== "bar"
        ? NowPlayingService.viewFor(NowPlayingService.transferTo) : null
    readonly property var sourceView: NowPlayingService.transferFrom !== "bar"
        ? NowPlayingService.viewFor(NowPlayingService.transferFrom) : null
    readonly property var destinationMotion: destinationView?.panelMotion ?? null
    // Allow the bar and either live attached body during redirected journeys.
    // The snapshots remain fixed while only their visible viewport changes.
    readonly property real carrierBottom: Math.max(Theme.barHeight,
        panelBottom(sourceView), panelBottom(destinationView))

    // The clipping textures keep the same allocation throughout a flight.
    readonly property real coverResolution: Math.max(1, departure?.cover?.width ?? 1,
                                                     arrival?.cover?.width ?? 1)
    readonly property real coverScale: coordinate("cover", "width", 1) / coverResolution
    readonly property real textBlend: progress * progress * (3 - 2 * progress)

    readonly property color departureTitleColor: departure?.title?.color ?? Theme.colors.text
    readonly property color arrivalTitleColor: arrival?.title?.color ?? Theme.colors.text
    readonly property color departureArtistColor: departure?.artist?.color ?? Theme.colors.textDim
    readonly property color arrivalArtistColor: arrival?.artist?.color ?? Theme.colors.textDim
    readonly property real bend: departure && arrival
        ? Math.min(8, Math.abs(arrival.cover.y - departure.cover.y) * 0.06) : 0

    visible: NowPlayingService.moving && prepared
    color: "transparent"
    aboveWindows: true
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    // Reuse the toast's no_anim compositor rule: movement happens in QML.
    WlrLayershell.namespace: "quickshell:nowplaying"
    mask: Region {}
    // A stable surface size avoids a configure round trip when direction changes.
    implicitHeight: Math.min(screen?.height ?? 400, 400)
    onBackingWindowVisibleChanged: if (backingWindowVisible) Qt.callLater(startFlight)
    onWidthChanged: if (awaitingStart) Qt.callLater(startFlight)

    function valid(frame) {
        if (!frame || !frame.screen)
            return false;
        for (const name of ["cover", "title", "artist"]) {
            const part = frame[name];
            if (!part || !isFinite(part.x) || !isFinite(part.y)
                    || !isFinite(part.width) || !isFinite(part.height)
                    || part.width <= 0 || part.height <= 0)
                return false;
        }
        return true;
    }

    function captureView(name) {
        const view = NowPlayingService.viewFor(name);
        if (!view || !view.QsWindow.window || !view.capture)
            return null;
        return view.capture();
    }

    function panelBottom(view) {
        const window = view?.QsWindow.window;
        return window ? (window.margins?.top ?? 0) + Math.max(0, view.revealBottom) : 0;
    }

    function panelBounds(view) {
        const window = view?.QsWindow.window;
        const surface = view?.panelSurface;
        if (!surface || !window?.screen || !window.contentItem)
            return Qt.rect(0, 0, 0, 0);
        const originX = window.anchors?.right && !window.anchors?.left
            ? window.screen.width - window.width - (window.margins?.right ?? 0)
            : (window.margins?.left ?? 0);
        const point = window.contentItem.mapFromItem(surface, 0, 0);
        return Qt.rect(originX + point.x, (window.margins?.top ?? 0) + point.y,
            surface.width, surface.height);
    }

    function remainingDuration() {
        if (destinationMotion?.expandFromBar && destinationMotion.opened
                && destinationMotion.progress < 1)
            return Math.max(1, Math.round(destinationMotion.openDuration
                * (1 - destinationMotion.progress)));
        const motion = sourceView?.panelMotion;
        return motion?.expandFromBar && !motion.opened && motion.progress > 0
            ? Math.max(1, Math.round(motion.closeDuration * motion.progress))
            : NowPlayingService.transferDuration;
    }

    function mix(a, b) {
        return a + (b - a) * progress;
    }

    function coordinate(part, field, fallback) {
        if (!departure || !arrival)
            return fallback ?? 0;
        const first = departure[part][field] ?? fallback ?? 0;
        const last = arrival[part][field] ?? fallback ?? 0;
        const value = mix(first, last);
        // A shallow arc softens the diagonal without overshooting the target.
        return field === "y" ? value + Math.sin(Math.PI * progress) * bend : value;
    }

    function blendColor(first, last) {
        return Qt.rgba(mix(first.r, last.r), mix(first.g, last.g),
                       mix(first.b, last.b), mix(first.a, last.a));
    }

    function renderedPart(name) {
        const part = {
            x: coordinate(name, "x"), y: coordinate(name, "y"),
            width: coordinate(name, "width"), height: coordinate(name, "height")
        };
        if (name === "cover") {
            part.radius = coordinate(name, "radius", Theme.radius);
        } else {
            part.fontSize = coordinate(name, "fontSize", 12);
            part.color = name === "title"
                ? blendColor(departureTitleColor, arrivalTitleColor)
                : blendColor(departureArtistColor, arrivalArtistColor);
            part.bold = progress < 0.5 ? departure[name].bold : arrival[name].bold;
        }
        return part;
    }

    function renderedFrame() {
        if (!prepared || !departure || !arrival)
            return null;
        return { track: track, cover: renderedPart("cover"),
                 title: renderedPart("title"), artist: renderedPart("artist"), screen: screen };
    }

    function isCurrent(serial) {
        return activeSerial === serial && NowPlayingService.moving
            && NowPlayingService.transferSerial === serial;
    }

    function finish(serial) {
        if (!isCurrent(serial))
            return;
        NowPlayingService.finishTransfer(serial);
        // Finishing may synchronously request another journey.
        if (activeSerial === serial)
            prepared = false;
    }

    function barTransferHidden() {
        return NowPlayingService.barHidden
            && (NowPlayingService.transferFrom === "bar" || NowPlayingService.transferTo === "bar");
    }

    function begin(serial) {
        // Redirect from the painted position without unmapping the surface or
        // exposing one of the hidden endpoint views between the two flights.
        const interrupted = renderedFrame() || pendingFrame
            || captureView(NowPlayingService.transferFrom);
        flight.stop();
        prepareLayout.stop();
        awaitingStart = false;
        pendingFrame = interrupted;
        activeSerial = serial;
        prepareAttempts = 0;
        NowPlayingService.transferReady = prepared;
        if (barTransferHidden()) {
            finish(serial);
            return;
        }
        // callLater lets layouts polish once. A timer only retries a surface
        // that is still waiting for its first Wayland configure.
        Qt.callLater(prepareFlight);
    }

    function prepareFlight() {
        if (!isCurrent(activeSerial)) {
            prepareLayout.stop();
            return;
        }
        if (barTransferHidden()) {
            finish(activeSerial);
            return;
        }
        const view = NowPlayingService.viewFor(NowPlayingService.transferTo);
        const window = view?.QsWindow.window;
        const source = pendingFrame || captureView(NowPlayingService.transferFrom);
        if (valid(source) && view && !view.sameTrack(source.track, view.displayedTrack))
            view.setTrack(source.track, false);
        const target = captureView(NowPlayingService.transferTo);
        prepareAttempts += 1;
        const laidOut = window?.backingWindowVisible && window.contentItem
            && window.width > 0 && window.height > 0
            && Math.abs(window.contentItem.width - window.width) < 1
            && Math.abs(window.contentItem.height - window.height) < 1;
        if (!laidOut || !valid(target)) {
            if (prepareAttempts >= 20) {
                prepareLayout.stop();
                finish(activeSerial);
            } else {
                prepareLayout.restart();
            }
            return;
        }
        prepareLayout.stop();
        if (!valid(source) || source.screen !== target.screen) {
            finish(activeSerial);
            return;
        }
        // A different toast/popup opened during a flight is the only case
        // that needs a new mapping order. Keep ownership on the carrier and
        // reuse the captured frame, so its source never flashes back on.
        const remap = prepared && NowPlayingService.transferTo !== "bar"
            && window !== layeredDestination;
        if (remap)
            prepared = false;
        if (NowPlayingService.transferTo !== "bar")
            layeredDestination = window;
        screen = target.screen;
        departure = source;
        arrival = target;
        track = source.track || NowPlayingService.transferTrack || target.track;
        // A redirected transfer keeps the captured song and its position.
        NowPlayingService.transferTrack = track;
        progress = 0;
        awaitingStart = true;
        prepared = true;
        pendingFrame = null;
        Qt.callLater(startFlight);
    }

    function startFlight() {
        if (!awaitingStart || !isCurrent(activeSerial) || !backingWindowVisible
                || !contentItem || contentItem.width <= 0)
            return;
        // The destination's connecting curves form while the source keeps
        // ownership. Closing or redirecting that request cannot strand a wait.
        if (destinationMotion?.expandFromBar) {
            if (!destinationMotion.opened) {
                awaitingStart = false;
                finish(activeSerial);
                return;
            }
            if (destinationMotion.joinProgress < 1)
                return;
        }
        awaitingStart = false;
        // The source retains ownership until the transfer surface exists.
        NowPlayingService.startTransfer(activeSerial);
        // A toast starts contracting when ownership leaves it, so read its
        // remaining time after the handover updates its requested state.
        flightDuration = remainingDuration();
        flight.start();
    }

    Timer {
        id: prepareLayout
        interval: 8
        onTriggered: root.prepareFlight()
    }

    Timer {
        interval: 8
        repeat: true
        running: root.awaitingStart
        onTriggered: root.startFlight()
    }

    Connections {
        target: root.destinationMotion
        function onJoinProgressChanged() {
            if (root.awaitingStart)
                Qt.callLater(root.startFlight);
        }
        function onOpenedChanged() {
            if (root.awaitingStart)
                Qt.callLater(root.startFlight);
        }
    }

    Connections {
        target: NowPlayingService

        function onTransferRequested(serial) { root.begin(serial); }
        function onBarHiddenChanged() {
            if (root.barTransferHidden() && root.isCurrent(root.activeSerial))
                root.finish(root.activeSerial);
        }
        function onMovingChanged() {
            if (!NowPlayingService.moving) {
                flight.stop();
                prepareLayout.stop();
                root.prepared = false;
                root.awaitingStart = false;
                root.pendingFrame = null;
            }
        }
    }

    NumberAnimation {
        id: flight
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.flightDuration
        easing.type: Easing.OutCubic
        onFinished: root.finish(root.activeSerial)
    }

    Item {
        id: carrierViewport
        width: root.width
        height: Math.min(root.height, root.carrierBottom)
        clip: true
        // Map the transparent native carrier first; paint only when the source
        // has handed over so waiting never doubles the source's glyphs.
        visible: NowPlayingService.transferReady
    }

    // Keep the mask fixed in screen coordinates while the labels move. Its
    // panel shapes follow the same reveal and curves as the visible surfaces.
    Item {
        id: flightTextMask
        parent: carrierViewport
        width: root.width
        height: root.height

        Rectangle {
            width: parent.width
            height: Theme.barHeight
            color: "white"
        }
        PanelTextMask { view: root.sourceView }
        PanelTextMask { view: root.destinationView }
    }

    ShaderEffectSource {
        id: flightTextMaskTexture
        parent: carrierViewport
        sourceItem: flightTextMask
        hideSource: true
        visible: false
    }

    component PanelTextMask: AttachedPanel {
        required property var view
        readonly property var surface: view?.panelSurface ?? null
        readonly property rect bounds: root.panelBounds(view)
        x: bounds.x
        y: bounds.y
        width: bounds.width
        height: bounds.height
        visible: !!view?.QsWindow.window?.backingWindowVisible
        color: "white"
        cornerRadius: surface?.cornerRadius ?? 0
        joinProgress: surface?.joinProgress ?? 0
        revealProgress: surface?.revealProgress ?? 0
        attachRightEdge: surface?.attachRightEdge ?? true
        edgeSoftness: surface?.edgeSoftness ?? 2
    }

    Item {
        id: flightText
        parent: carrierViewport
        width: root.width
        height: root.height
        layer.enabled: true
        layer.effect: OpacityMask { maskSource: flightTextMaskTexture }
    }

    ClippingRectangle {
        id: flyingCover
        parent: carrierViewport
        x: root.coordinate("cover", "x")
        y: root.coordinate("cover", "y")
        width: root.coverResolution
        height: root.coverResolution
        // Adjust only the fixed-size clipping mask, never its texture size.
        radius: root.coordinate("cover", "radius", Theme.radius) / Math.max(0.001, root.coverScale)
        color: Theme.colors.surface0
        contentInsideBorder: false
        antialiasing: true
        transform: Scale {
            xScale: root.coverScale
            yScale: root.coordinate("cover", "height", 1) / root.coverResolution
        }

        Image {
            id: cover
            anchors.fill: parent
            source: root.track?.artUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            visible: status === Image.Ready
        }

        Text {
            id: coverPlaceholder
            anchors.centerIn: parent
            text: "music_note"
            visible: cover.status !== Image.Ready
            font.family: Theme.iconFamily
            font.pixelSize: 34
            color: Theme.colors.textDim
            transform: Scale {
                origin.x: coverPlaceholder.width / 2
                origin.y: coverPlaceholder.height / 2
                xScale: Math.min(34, Math.max(16, root.coordinate("cover", "width") * 0.5))
                    / (34 * Math.max(0.001, root.coverScale))
                yScale: xScale
            }
        }
    }

    // Both endpoint labels have immutable font metrics and elision widths.
    // Movement only transforms their existing glyphs; the gentle crossfade
    // changes wrapping/elision without re-laying out text every animation tick.
    component FlightLabel: Text {
        parent: flightText
        required property string part
        required property bool destination
        readonly property var frame: destination ? root.arrival : root.departure
        readonly property var geometry: frame ? frame[part] : null
        readonly property real fontScale: root.coordinate(part, "fontSize", 12)
            / Math.max(1, geometry?.fontSize ?? 12)

        x: root.coordinate(part, "x")
        y: root.coordinate(part, "y")
            + (root.coordinate(part, "height") - height * fontScale) / 2
        width: geometry?.width ?? 1
        height: geometry?.height ?? 1
        text: part === "title" ? root.track?.title || "Unknown track"
                              : root.track?.artist || root.track?.playerName || "Unknown artist"
        font.family: Theme.textFamily
        font.pixelSize: geometry?.fontSize ?? 12
        font.bold: geometry?.bold ?? (part === "title")
        color: geometry?.color ?? Theme.colors.text
        opacity: destination ? root.textBlend : 1 - root.textBlend
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        // Qt's distance-field glyph cache remains sharp under transform scaling.
        renderType: Text.QtRendering
        transform: Scale { xScale: fontScale; yScale: fontScale }
    }

    FlightLabel { part: "title"; destination: false }
    FlightLabel { part: "title"; destination: true }
    FlightLabel { part: "artist"; destination: false }
    FlightLabel { part: "artist"; destination: true }
}
