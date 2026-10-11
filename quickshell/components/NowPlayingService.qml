pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// A single owner for the song's visible artwork and labels. The bar, toast and
// popup retain their geometry while immutable snapshots travel between them.
QtObject {
    id: root

    readonly property int transferDuration: 340
    readonly property int toastDuration: 5000
    readonly property var emptyTrack: ({ key: "", title: "", artist: "", artUrl: "", album: "", playerName: "" })
    property var latestTrack: emptyTrack
    property var barView: null
    property var toastView: null
    property var popupView: null
    property var mediaEndpoints: []
    property var activeScreen: null
    property string owner: "bar"
    property bool moving: false
    property bool transferReady: false
    property string transferFrom: "bar"
    property string transferTo: "bar"
    property var transferTrack: emptyTrack
    property int transferSerial: 0
    property bool toastMapped: false
    property bool toastClosing: false
    property bool toastStandalone: false
    readonly property bool barHidden: activeScreen ? OverlayService.topMargin(activeScreen) === 0 : false
    property bool popupMapped: false
    property bool popupOpen: false
    readonly property bool mediaPopupVisible: popupOpen
    property bool wasPlaying: false
    property bool pendingToast: false
    property int revision: 0
    readonly property string title: latestTrack.title
    readonly property string artist: latestTrack.artist
    readonly property string artUrl: latestTrack.artUrl
    readonly property string playerName: latestTrack.playerName

    property var artworkCache: ({})
    property string pendingArtwork: ""

    signal transferRequested(int serial)

    function registerViews(screen, bar, popup) {
        if (!screen)
            return;
        mediaEndpoints = mediaEndpoints.filter(endpoint => endpoint.bar !== bar)
            .concat([{ screen: screen, bar: bar, popup: popup }]);
        bar.setTrack(latestTrack, false);
        if (!barView || screen.name === Hyprland.focusedMonitor?.name
                && !popupMapped && !toastMapped && !moving)
            activateScreen(screen);
    }

    function unregisterViews(bar) {
        mediaEndpoints = mediaEndpoints.filter(endpoint => endpoint.bar !== bar);
        if (barView !== bar)
            return;
        setPopupOpen(false);
        if (moving)
            finishTransfer(transferSerial);
        barView = null;
        popupView = null;
        activeScreen = null;
        if (mediaEndpoints.length)
            activateScreen(mediaEndpoints[0].screen);
    }

    function activateScreen(screen) {
        const endpoint = mediaEndpoints.find(candidate => candidate.screen === screen);
        if (!endpoint || barView === endpoint.bar)
            return;
        // Finish the old output's handoff before replacing its endpoints.
        setPopupOpen(false);
        if (moving)
            finishTransfer(transferSerial);
        activeScreen = screen;
        barView = endpoint.bar;
        popupView = endpoint.popup;
        if (owner === "bar")
            barView.setTrack(latestTrack, false);
    }

    function syncBars() {
        for (const endpoint of mediaEndpoints) {
            if (endpoint.bar !== barView)
                endpoint.bar.setTrack(latestTrack, false);
        }
    }

    function artworkUrl(source) {
        if (!/^file:.*\.webp(?:[?#].*)?$/i.test(source))
            return source;
        if (artworkCache[source] !== undefined)
            return artworkCache[source];
        if (artworkDecoder.running) {
            if (artworkDecoder.sourceUrl !== source)
                pendingArtwork = source;
        } else {
            artworkDecoder.sourceUrl = source;
            artworkDecoder.command = ["python3", Quickshell.shellPath("scripts/media-artwork.py"), source];
            artworkDecoder.running = true;
        }
        return "";
    }

    property Process artworkDecoder: Process {
        property string sourceUrl: ""
        stdout: StdioCollector { id: artworkOutput }
        onExited: function(exitCode) {
            const cache = Object.assign({}, root.artworkCache);
            cache[sourceUrl] = exitCode === 0 ? artworkOutput.text.trim() : "";
            root.artworkCache = cache;
            metadataTimer.restart();
            selectedTimer.restart();
            const next = root.pendingArtwork;
            root.pendingArtwork = "";
            if (next)
                root.artworkUrl(next);
        }
    }

    function ownsView(name) {
        if (name === "bar" && barHidden)
            return false;
        return moving ? !transferReady && transferFrom === name : owner === name;
    }

    function viewFor(name) {
        return name === "bar" ? barView : name === "toast" ? toastView : popupView;
    }

    function snapshot(player) {
        if (!player || !(player.trackTitle || player.trackArtist))
            return emptyTrack;
        const title = String(player.trackTitle || "Unknown track");
        const artist = String(player.trackArtist || "");
        const album = String(player.trackAlbum || "");
        const source = String(player.dbusName || MediaService.playerName(player));
        // Artwork can arrive later than the metadata; it is not a new song.
        const trackId = String(player.uniqueId || "");
        // uniqueId advances on every track change, including a return to a
        // previous song. History needs an identity independent of that counter.
        return { key: source + "\n" + (trackId || title + "\n" + artist),
            historyKey: JSON.stringify([source, title, artist, album]),
            title: title, artist: artist, artUrl: artworkUrl(String(player.trackArtUrl || "")),
            album: album, playerName: MediaService.playerName(player) };
    }

    function refresh() {
        const next = snapshot(MediaService.player);
        const playing = !!MediaService.player?.isPlaying;
        const changed = next.key !== latestTrack.key;
        const started = playing && !wasPlaying;
        wasPlaying = playing;
        latestTrack = next;
        syncBars();
        if (!next.key.length) {
            reset();
            return;
        }
        if (changed)
            revision += 1;
        if (popupOpen) {
            refreshPopup();
            return;
        }
        if (playing && (changed || started)) {
            showToast();
        } else if (!moving) {
            const view = viewFor(owner);
            if (view)
                view.setTrack(next, changed && owner !== "bar");
        }
    }

    function refreshPopup() {
        if (popupOpen && !moving && popupView)
            popupView.setTrack(snapshot(MediaService.selectedPlayer), true);
    }

    function reset() {
        dismissTimer.stop();
        transferSerial += 1;
        moving = false;
        owner = "bar";
        toastMapped = false;
        toastClosing = false;
        popupOpen = false;
        popupMapped = false;
        pendingToast = false;
        for (const view of [barView, toastView, popupView]) {
            if (view)
                view.setTrack(emptyTrack, false);
        }
    }

    function moveTo(destination) {
        dismissTimer.stop();
        const source = viewFor(owner);
        const target = viewFor(destination);
        if (!target)
            return;
        // A fullscreen application covers the bar. Never animate from or to
        // that invisible endpoint; the toast presents itself horizontally.
        if (barHidden && (owner === "bar" || destination === "bar")) {
            transferSerial += 1;
            moving = false;
            transferReady = false;
            owner = destination;
            target.setTrack(destination === "popup" ? snapshot(MediaService.selectedPlayer) : latestTrack, false);
            completeOwnership();
            return;
        }
        if (!moving && source)
            source.settle();
        const track = moving ? transferTrack : source?.displayedTrack;
        if (!track?.key || !source || owner === destination && !moving) {
            owner = destination;
            target.setTrack(destination === "popup" ? snapshot(MediaService.selectedPlayer) : latestTrack, false);
            completeOwnership();
            return;
        }
        transferReady = false;
        transferFrom = owner;
        transferTo = destination;
        transferTrack = track;
        target.setTrack(track, false);
        owner = destination;
        moving = true;
        transferSerial += 1;
        transferRequested(transferSerial);
    }

    function startTransfer(serial) {
        if (serial !== transferSerial || !moving)
            return;
        transferReady = true;
    }

    function finishTransfer(serial) {
        if (serial !== transferSerial || !moving)
            return;
        moving = false;
        completeOwnership();
    }

    function completeOwnership() {
        if (owner === "bar") {
            if (barView && !pendingToast)
                barView.setTrack(latestTrack, false);
            toastMapped = false;
            popupMapped = false;
            // A skip during the return flight gets its own toast after landing.
            if (pendingToast && !popupOpen && !OsdService.overlayVisible) {
                pendingToast = false;
                Qt.callLater(showToast);
            }
        } else if (owner === "toast") {
            if (toastView)
                toastView.setTrack(latestTrack, true);
            popupMapped = false;
            if (!OsdService.overlayVisible && !dismissTimer.running)
                dismissTimer.restart();
        } else {
            if (popupView)
                popupView.setTrack(snapshot(MediaService.selectedPlayer), true);
            toastMapped = false;
        }
    }

    function showToast() {
        if (!latestTrack.key || popupOpen)
            return;
        if (!toastMapped && !moving && mediaEndpoints.length) {
            const focused = mediaEndpoints.find(endpoint => endpoint.screen.name === Hyprland.focusedMonitor?.name);
            if (focused)
                activateScreen(focused.screen);
        }
        if (OsdService.overlayVisible) {
            pendingToast = true;
            return;
        }
        if (moving && owner === "bar") {
            pendingToast = true;
            return;
        }
        pendingToast = false;
        toastClosing = false;
        if (!toastMapped)
            toastStandalone = barHidden || !barView?.displayedTrack?.key;
        toastMapped = true;
        if (owner === "toast") {
            if (!moving && toastView)
                toastView.setTrack(latestTrack, true);
        } else {
            moveTo("toast");
        }
        dismissTimer.restart();
    }

    function dismissToast() {
        pendingToast = false;
        if (owner === "toast" && barHidden) {
            dismissTimer.stop();
            toastClosing = true;
        } else if (owner === "toast")
            moveTo("bar");
        else
            toastMapped = false;
    }

    function finishToastExit() {
        if (!toastClosing || popupOpen)
            return;
        toastClosing = false;
        toastMapped = false;
        moveTo("bar");
    }

    function fullscreenChanged() {
        if (barHidden && moving && (transferFrom === "bar" || transferTo === "bar"))
            finishTransfer(transferSerial);
        if (!barHidden && toastClosing) {
            toastClosing = false;
            dismissToast();
        }
    }

    onBarHiddenChanged: fullscreenChanged()

    function setPopupOpen(open) {
        if (popupOpen === open)
            return;
        pendingToast = false;
        popupOpen = open;
        if (open) {
            toastClosing = false;
            MediaService.selectCurrentPlayer();
            popupMapped = true;
            moveTo("popup");
        } else if (owner === "popup") {
            moveTo("bar");
        }
    }

    // MPRIS emits one postTrackChanged after its metadata fields are updated.
    // Briefly coalesce source/state changes too, without racing playerctl.
    property Timer metadataTimer: Timer {
        interval: 45
        onTriggered: root.refresh()
    }
    property Timer selectedTimer: Timer {
        interval: 45
        onTriggered: root.refreshPopup()
    }
    property Timer dismissTimer: Timer {
        interval: root.toastDuration - root.transferDuration
        onTriggered: root.dismissToast()
    }
    property Connections activeSource: Connections {
        target: MediaService
        function onPlayerChanged() { metadataTimer.restart(); }
        function onSelectedPlayerChanged() { selectedTimer.restart(); }
    }
    property Connections activeMetadata: Connections {
        target: MediaService.player
        function onPostTrackChanged() { metadataTimer.restart(); }
        function onPlaybackStateChanged() { metadataTimer.restart(); }
        function onMetadataChanged() { metadataTimer.restart(); }
    }
    property Connections selectedMetadata: Connections {
        target: MediaService.selectedPlayer
        function onPostTrackChanged() { selectedTimer.restart(); }
        function onMetadataChanged() { selectedTimer.restart(); }
    }
    property Connections osd: Connections {
        target: OsdService
        function onOverlayVisibleChanged() {
            if (OsdService.overlayVisible) {
                dismissTimer.stop();
            } else if (!root.popupOpen && (root.pendingToast || root.owner === "toast")) {
                root.showToast();
            }
        }
    }
    onBarViewChanged: if (barView && owner === "bar" && !moving) barView.setTrack(latestTrack, false)
    Component.onCompleted: metadataTimer.restart()
}
