const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const serviceSource = fs.readFileSync(path.join(__dirname, "..", "components", "NowPlayingService.qml"), "utf8");
const viewSource = fs.readFileSync(path.join(__dirname, "..", "widgets", "MediaTrackView.qml"), "utf8");
const overlaySource = fs.readFileSync(path.join(__dirname, "..", "components", "OverlayService.qml"), "utf8");

// Execute the production QML JavaScript with deterministic animation/timer
// boundaries. No MPRIS or compositor is required, and no player is modified.
// This scanner extracts balanced blocks, ignoring comments and quoted braces.
function blockAt(source, opening) {
    let depth = 0;
    let quote = "";
    let comment = "";
    for (let i = opening; i < source.length; ++i) {
        const ch = source[i];
        const next = source[i + 1];
        if (comment === "line") {
            if (ch === "\n") comment = "";
        } else if (comment === "block") {
            if (ch === "*" && next === "/") { comment = ""; ++i; }
        } else if (quote) {
            if (ch === "\\") ++i;
            else if (ch === quote) quote = "";
        } else if (ch === "/" && next === "/") {
            comment = "line";
            ++i;
        } else if (ch === "/" && next === "*") {
            comment = "block";
            ++i;
        } else if (ch === "\"" || ch === "'" || ch === "`") {
            quote = ch;
        } else if (ch === "{") {
            ++depth;
        } else if (ch === "}" && --depth === 0) {
            return source.slice(opening, i + 1);
        }
    }
    throw new Error("Unclosed QML JavaScript block");
}

function installFunctions(source, context) {
    for (const match of source.matchAll(/^    function \w+\([^\n]*\)\s*(?::\s*\w+\s*)?\{/gm)) {
        const opening = match.index + match[0].lastIndexOf("{");
        const declaration = source.slice(match.index, opening).replace(/\)\s*:\s*\w+\s*$/, ") ");
        vm.runInContext(declaration + blockAt(source, opening), context);
    }
}

function callback(source, marker, property, context) {
    const beginning = source.indexOf(marker);
    assert.notEqual(beginning, -1, `Missing QML object ${marker}`);
    const propertyIndex = source.indexOf(property, beginning);
    assert.notEqual(propertyIndex, -1, `Missing callback ${property}`);
    const opening = source.indexOf("{", propertyIndex);
    return vm.runInContext("(function() " + blockAt(source, opening) + ")", context);
}

function makeView(mode) {
    const deferred = [];
    const context = vm.createContext({
        mode,
        width: mode === "popup" ? 484 : mode === "toast" ? 288 : 210,
        spacing: mode === "popup" ? 18 : mode === "toast" ? 11 : 8,
        coverSize: mode === "popup" ? 164 : mode === "toast" ? 42 : 32,
        displayedTrack: { key: "", title: "", artist: "", artUrl: "", album: "", playerName: "" },
        targetTrack: null,
        motionPhase: "idle",
        slideProgress: 0,
        activeBuffer: 0,
        Image: { Loading: 2, Ready: 1, Error: 3 },
        Qt: { callLater(fn) { deferred.push(fn); } },
    });
    context.root = context;
    context.swipeDistance = context.width + context.spacing;
    context.textWidth = context.width - context.coverSize - context.spacing;
    const placeStart = viewSource.indexOf("function place(position)");
    assert.notEqual(placeStart, -1);
    const placeBlock = blockAt(viewSource, viewSource.indexOf("{", placeStart));
    const cards = [0, 1].map(() => {
        const card = {
            track: context.displayedTrack,
            artworkVisible: false,
            coverStatus: context.Image.Ready,
            contentItem: { x: 0 }, coverItem: { x: 0 }, metadataItem: { x: 0 },
            restartScroll() {},
        };
        const cardContext = vm.createContext({ root: context,
            content: card.contentItem, cover: card.coverItem, metadata: card.metadataItem });
        card.place = vm.runInContext("(function(position) " + placeBlock + ")", cardContext);
        return card;
    });
    Object.defineProperties(context, {
        activeCard: { get() { return cards[context.activeBuffer]; } },
        nextCard: { get() { return cards[1 - context.activeBuffer]; } },
    });
    installFunctions(viewSource, context);
    for (const name of ["preloadTimeout", "swipeReady"]) {
        const definition = viewSource.slice(viewSource.indexOf("id: " + name));
        const triggered = definition.match(/^        onTriggered: (.+)$/m)[1];
        context[name] = {
            running: false,
            restart() { this.running = true; },
            stop() { this.running = false; },
            fire() {
                assert.equal(this.running, true, `${mode}.${name} must be running`);
                this.running = false;
                vm.runInContext(triggered, context);
            },
        };
    }
    const swipeDefinition = viewSource.slice(viewSource.indexOf("id: swipe\n"));
    const tracks = [...swipeDefinition.matchAll(/XAnimator\s*\{/g)].map(match => {
        const definition = blockAt(swipeDefinition, match.index + match[0].lastIndexOf("{"));
        return Object.fromEntries(["target", "from", "to"].map(name =>
            [name, definition.match(new RegExp("^            " + name + ": (.+)$", "m"))[1]]));
    });
    const finished = swipeDefinition.match(/^        onFinished: (.+)$/m)[1];
    context.swipe = {
        running: false,
        tracks: [],
        start() {
            this.running = true;
            this.tracks = tracks.map(track => Object.fromEntries(Object.entries(track)
                .map(([name, expression]) => [name, vm.runInContext(expression, context)])));
            this.sample(0);
        },
        sample(fraction) {
            assert.equal(this.running, true);
            for (const track of this.tracks)
                track.target.x = track.from + (track.to - track.from) * fraction;
        },
        stop() { this.running = false; },
        finish() {
            this.sample(1);
            this.running = false;
            vm.runInContext(finished, context);
        },
    };
    context.flush = () => { while (deferred.length) deferred.shift()(); };
    context.beginSwipe = () => {
        context.flush();
        context.swipeReady.fire();
    };
    context.completeSwipe = () => {
        if (context.motionPhase === "preload") context.beginSwipe();
        context.swipe.finish();
        context.flush();
    };
    return context;
}

function makePlayer(number = 1, extra = {}) {
    return {
        dbusName: "org.mpris.MediaPlayer2.test",
        identity: "Test player",
        uniqueId: number,
        trackTitle: "Track " + number,
        trackArtist: "Artist " + number,
        trackAlbum: "Album",
        trackArtUrl: "file:///cover-" + number + ".png",
        isPlaying: true,
        ...extra,
    };
}

test("overlay placement distinguishes real fullscreen from maximized windows on its own output", () => {
    const context = vm.createContext({
        Hyprland: { monitorFor(screen) { return screen.monitor; } },
        Theme: { barHeight: 42 },
    });
    installFunctions(overlaySource, context);
    function screen(hasFullscreen, ...modes) {
        return { monitor: { activeWorkspace: {
            hasFullscreen,
            toplevels: { values: modes.map(fullscreen => ({ lastIpcObject: { fullscreen } })) },
        } } };
    }
    assert.equal(context.topMargin(null), 42);
    assert.equal(context.topMargin(screen(false, 0)), 42);
    assert.equal(context.topMargin(screen(true, 1)), 42, "maximized windows retain the bar");
    assert.equal(context.topMargin(screen(true, 2)), 0);
    assert.equal(context.topMargin(screen(true, 1, 2)), 0, "inspect all windows on the output");
    assert.equal(context.topMargin(screen(false, 0)), 42, "another output retains its own bar margin");
    assert.equal(context.topMargin({ monitor: { activeWorkspace: {
        hasFullscreen: true, toplevels: { values: [{ lastIpcObject: {} }] },
    } } }), 42, "incomplete IPC metadata must not hide the bar");
});

function makeService() {
    const deferred = [];
    const transfers = [];
    const context = vm.createContext({
        Qt: { callLater(fn) { deferred.push(fn); } },
        MediaService: {
            player: null,
            selectedPlayer: null,
            playerName(player) { return player?.identity || "Unknown player"; },
            selectCurrentPlayer() { this.selectedPlayer = this.player; },
        },
        OsdService: { overlayVisible: false },
        transferRequested(serial) {
            transfers.push({ serial, from: context.transferFrom, to: context.transferTo,
                track: context.transferTrack });
        },
        dismissTimer: {
            running: false,
            restart() { this.running = true; },
            stop() { this.running = false; },
        },
    });
    context.root = context;
    installFunctions(serviceSource, context);
    // Initialize the actual scalar QML defaults instead of duplicating the
    // coordinator's initial state in the harness.
    for (const match of serviceSource.matchAll(/^    (?:readonly )?property (?:int|var|string|bool) (\w+): (.+)$/gm)) {
        context[match[1]] = vm.runInContext(match[2], context);
    }
    context.barView = makeView("bar");
    context.toastView = makeView("toast");
    context.popupView = makeView("popup");
    const osdChanged = callback(serviceSource, "property Connections osd:", "function onOverlayVisibleChanged()", context);
    return {
        service: context,
        transfers,
        update(player) {
            context.MediaService.player = player;
            if (!context.MediaService.selectedPlayer) context.MediaService.selectedPlayer = player;
            context.refresh();
        },
        finishTransfer() { context.finishTransfer(context.transferSerial); },
        flush() {
            while (deferred.length) deferred.shift()();
        },
        osd(visible) {
            context.OsdService.overlayVisible = visible;
            osdChanged();
        },
        fullscreen(hidden) {
            context.barHidden = hidden;
            context.fullscreenChanged();
        },
        landOnBar() {
            context.dismissToast();
            this.finishTransfer();
            this.flush();
        },
    };
}

test("first playback belongs to the toast until its return flight finishes", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    assert.equal(s.owner, "toast");
    assert.equal(s.toastMapped, true);
    assert.equal(s.moving, false);
    assert.equal(s.barView.displayedTrack.key, "");
    assert.equal(s.toastView.displayedTrack.title, "Track 1");
    assert.equal(s.dismissTimer.running, true);

    s.dismissToast();
    assert.equal(s.moving, true);
    assert.equal(s.owner, "bar");
    assert.equal(s.toastMapped, true, "keep the origin mapped during its flight");
    assert.equal(s.transferTrack.title, "Track 1");
    h.finishTransfer();
    assert.equal(s.moving, false);
    assert.equal(s.toastMapped, false);
    assert.equal(s.barView.displayedTrack.title, "Track 1");
});

test("track changes carry the previous bar song before swiping the new song in from the right", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    h.landOnBar();
    h.update(makePlayer(2));
    assert.equal(s.transferFrom, "bar");
    assert.equal(s.transferTo, "toast");
    assert.equal(s.transferTrack.title, "Track 1");
    assert.equal(s.toastView.displayedTrack.title, "Track 1");
    h.finishTransfer();
    assert.equal(s.toastView.motionPhase, "preload");
    assert.equal(s.toastView.displayedTrack.title, "Track 1");
    assert.equal(s.toastView.targetTrack.title, "Track 2");
    s.toastView.beginSwipe();
    s.toastView.swipe.sample(0.5);
    assert.ok(s.toastView.activeCard.contentItem.x < 0, "old card travels left");
    assert.ok(s.toastView.nextCard.contentItem.x > 0, "new card enters from right");
    assert.equal(s.toastView.displayedTrack.title, "Track 1", "freeze outgoing metadata throughout motion");
    s.toastView.completeSwipe();
    assert.equal(s.toastView.displayedTrack.title, "Track 2");
    assert.equal(s.toastView.motionPhase, "idle");
    assert.equal(s.toastView.activeCard.contentItem.x, 0);
});

test("popup opening transfers ownership, track changes swipe there, and closing restores the bar", () => {
    const h = makeService();
    const s = h.service;
    const player = makePlayer();
    h.update(player);
    h.landOnBar();
    s.setPopupOpen(true);
    assert.equal(s.popupOpen, true);
    assert.equal(s.popupMapped, true);
    assert.equal(s.owner, "popup");
    assert.equal(s.moving, true);
    h.finishTransfer();
    assert.equal(s.popupView.displayedTrack.title, "Track 1");
    Object.assign(player, makePlayer(2));
    h.update(player);
    assert.equal(s.toastMapped, false);
    assert.equal(s.popupView.motionPhase, "preload");
    s.popupView.completeSwipe();
    s.setPopupOpen(false);
    assert.equal(s.transferTrack.title, "Track 2");
    assert.equal(s.popupMapped, true);
    h.finishTransfer();
    assert.equal(s.owner, "bar");
    assert.equal(s.popupMapped, false);
    assert.equal(s.barView.displayedTrack.title, "Track 2");
});

test("rapid skips during the outbound flight preserve the old image and show only the latest destination", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    h.landOnBar();
    h.update(makePlayer(2));
    const serial = s.transferSerial;
    h.update(makePlayer(3));
    h.update(makePlayer(4));
    assert.equal(s.transferSerial, serial);
    assert.equal(s.transferTrack.title, "Track 1");
    h.finishTransfer();
    assert.equal(s.toastView.targetTrack.title, "Track 4");
    assert.equal(s.toastView.displayedTrack.title, "Track 1");
    s.toastView.completeSwipe();
    assert.equal(s.toastView.displayedTrack.title, "Track 4");
});

test("a skip during the return flight moves the old song back to the toast before the new-song swipe", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    s.dismissToast();
    h.update(makePlayer(2));
    assert.equal(s.pendingToast, true);
    assert.equal(s.transferTrack.title, "Track 1");
    h.finishTransfer();
    h.flush();
    assert.equal(s.owner, "toast");
    assert.equal(s.moving, true);
    assert.equal(s.transferTrack.title, "Track 1");
    h.finishTransfer();
    assert.equal(s.toastView.displayedTrack.title, "Track 1");
    assert.equal(s.toastView.targetTrack.title, "Track 2");
    assert.equal(s.toastView.motionPhase, "preload");
});

test("late artwork on the same track updates in place without a new toast or swipe", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer(1, { trackArtUrl: "" }));
    h.landOnBar();
    const revision = s.revision;
    const transfers = h.transfers.length;
    h.update(makePlayer(1, { trackArtUrl: "file:///late-art.png" }));
    assert.equal(s.revision, revision);
    assert.equal(s.owner, "bar");
    assert.equal(s.toastMapped, false);
    assert.equal(h.transfers.length, transfers);
    assert.equal(s.barView.displayedTrack.artUrl, "file:///late-art.png");
    assert.equal(s.barView.motionPhase, "idle");
});

test("source removal cancels a flight and makes its stale completion harmless", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    s.dismissToast();
    const canceledSerial = s.transferSerial;
    h.update(null);
    assert.equal(s.owner, "bar");
    assert.equal(s.moving, false);
    assert.equal(s.toastMapped, false);
    assert.equal(s.popupMapped, false);
    assert.equal(s.dismissTimer.running, false);
    assert.equal(s.barView.displayedTrack.key, "");
    assert.equal(s.toastView.displayedTrack.key, "");
    h.update(makePlayer(2));
    s.finishTransfer(canceledSerial);
    assert.equal(s.owner, "toast");
    assert.equal(s.toastView.displayedTrack.title, "Track 2");
});

test("OSD defers a pending toast and resumes its dismissal after feedback ends", () => {
    const h = makeService();
    const s = h.service;
    h.osd(true);
    h.update(makePlayer());
    h.update(makePlayer(2));
    assert.equal(s.pendingToast, true);
    assert.equal(s.toastMapped, false);
    assert.equal(s.dismissTimer.running, false);
    h.osd(false);
    assert.equal(s.pendingToast, false);
    assert.equal(s.owner, "toast");
    assert.equal(s.toastView.displayedTrack.title, "Track 2");
    assert.equal(s.dismissTimer.running, true);
    h.osd(true);
    assert.equal(s.dismissTimer.running, false);
    h.osd(false);
    assert.equal(s.dismissTimer.running, true);
});

test("opening then immediately closing the popup supersedes the earlier transfer", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    h.landOnBar();
    s.setPopupOpen(true);
    const openingSerial = s.transferSerial;
    s.setPopupOpen(false);
    const closingSerial = s.transferSerial;
    assert.ok(closingSerial > openingSerial);
    s.finishTransfer(openingSerial);
    assert.equal(s.moving, true);
    assert.equal(s.owner, "bar");
    s.finishTransfer(closingSerial);
    assert.equal(s.moving, false);
    assert.equal(s.popupMapped, false);
    assert.equal(s.barView.displayedTrack.title, "Track 1");
});

test("rapid skips leave both moving cards immutable and then present the latest track", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    h.update(makePlayer(2));
    s.toastView.beginSwipe();
    h.update(makePlayer(3));
    s.toastView.swipe.sample(0.5);
    assert.equal(s.toastView.activeCard.track.title, "Track 1");
    assert.equal(s.toastView.nextCard.track.title, "Track 2");
    h.update(makePlayer(4));
    s.toastView.completeSwipe();
    assert.equal(s.toastView.displayedTrack.title, "Track 2");
    assert.equal(s.toastView.motionPhase, "preload");
    s.toastView.completeSwipe();
    assert.equal(s.toastView.motionPhase, "idle");
    assert.equal(s.toastView.displayedTrack.title, "Track 4");
});

test("late artwork during a flight is delivered on landing without replacing its frozen snapshot", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer(1, { trackArtUrl: "" }));
    s.dismissToast();
    const frozen = s.transferTrack;
    h.update(makePlayer(1, { trackArtUrl: "file:///late-art.png" }));
    assert.equal(s.transferTrack, frozen);
    assert.equal(s.transferTrack.artUrl, "");
    assert.equal(s.pendingToast, false);
    h.finishTransfer();
    assert.equal(s.barView.displayedTrack.artUrl, "file:///late-art.png");
    assert.equal(s.barView.motionPhase, "idle");
    assert.equal(s.toastMapped, false);
});

test("selecting a different popup source keeps the active bar source intact", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    h.landOnBar();
    s.setPopupOpen(true);
    h.finishTransfer();
    s.MediaService.selectedPlayer = makePlayer(9, { dbusName: "org.mpris.MediaPlayer2.other" });
    s.refreshPopup();
    s.popupView.completeSwipe();
    assert.equal(s.popupView.displayedTrack.title, "Track 9");
    assert.equal(s.latestTrack.title, "Track 1");
    assert.equal(s.toastMapped, false);
    s.setPopupOpen(false);
    h.finishTransfer();
    assert.equal(s.barView.displayedTrack.title, "Track 1");
    assert.equal(s.popupMapped, false);
});

test("the source stays visible during layout preparation and yields exclusively to the flight", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    assert.equal(s.ownsView("toast"), true);
    assert.equal(s.ownsView("bar"), false);
    s.dismissToast();
    assert.equal(s.ownsView("toast"), true);
    assert.equal(s.ownsView("bar"), false);
    s.transferReady = true;
    for (const surface of ["bar", "toast", "popup"])
        assert.equal(s.ownsView(surface), false);
    h.finishTransfer();
    assert.equal(s.ownsView("bar"), true);
    assert.equal(s.ownsView("toast"), false);
});

test("fullscreen playback shows a standalone toast and exits without a flight to the hidden bar", () => {
    const h = makeService();
    const s = h.service;
    h.fullscreen(true);
    h.update(makePlayer());
    assert.equal(s.toastStandalone, true);
    assert.equal(s.toastMapped, true);
    assert.equal(s.ownsView("toast"), true);
    assert.equal(s.ownsView("bar"), false);
    assert.equal(s.moving, false);
    assert.equal(h.transfers.length, 0);

    s.dismissToast();
    assert.equal(s.toastClosing, true);
    assert.equal(s.toastMapped, true, "retain the toast until its horizontal exit completes");
    assert.equal(s.ownsView("toast"), true);
    assert.equal(s.moving, false);
    s.finishToastExit();
    assert.equal(s.toastMapped, false);
    assert.equal(s.toastClosing, false);
    assert.equal(s.owner, "bar");
    assert.equal(s.ownsView("bar"), false);
    assert.equal(s.barView.displayedTrack.title, "Track 1");
    assert.equal(h.transfers.length, 0);
});

test("a skip after a fullscreen toast closes starts a fresh toast without borrowing the hidden bar", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    h.landOnBar();
    h.fullscreen(true);
    const transfers = h.transfers.length;
    h.update(makePlayer(2));
    assert.equal(s.toastStandalone, true);
    assert.equal(s.toastView.displayedTrack.title, "Track 2");
    assert.equal(s.ownsView("bar"), false);
    assert.equal(s.moving, false);
    s.dismissToast();
    s.finishToastExit();
    h.update(makePlayer(3));
    assert.equal(s.toastView.displayedTrack.title, "Track 3");
    assert.equal(s.moving, false);
    assert.equal(h.transfers.length, transfers);
});

test("new metadata during a fullscreen exit cancels closing and ignores its stale completion", () => {
    const h = makeService();
    const s = h.service;
    h.fullscreen(true);
    h.update(makePlayer());
    s.dismissToast();
    assert.equal(s.toastClosing, true);
    h.update(makePlayer(2));
    assert.equal(s.toastClosing, false);
    assert.equal(s.toastMapped, true);
    assert.equal(s.toastView.targetTrack.title, "Track 2");
    assert.equal(s.dismissTimer.running, true);
    s.finishToastExit();
    assert.equal(s.toastMapped, true);
    assert.equal(s.owner, "toast");
    assert.equal(s.moving, false);
    assert.equal(h.transfers.length, 0);
});

test("leaving fullscreen during a toast exit converts it into a return to the visible bar", () => {
    const h = makeService();
    const s = h.service;
    h.fullscreen(true);
    h.update(makePlayer());
    s.dismissToast();
    h.fullscreen(false);
    assert.equal(s.toastClosing, false);
    assert.equal(s.toastMapped, true);
    assert.equal(s.moving, true);
    assert.equal(s.transferFrom, "toast");
    assert.equal(s.transferTo, "bar");
    s.finishToastExit();
    assert.equal(s.moving, true, "a stale standalone exit cannot end the active return flight");
    h.finishTransfer();
    assert.equal(s.toastMapped, false);
    assert.equal(s.ownsView("bar"), true);
    assert.equal(s.barView.displayedTrack.title, "Track 1");
});

test("entering fullscreen cancels an active bar flight and stale callbacks cannot close its toast", () => {
    const h = makeService();
    const s = h.service;
    h.update(makePlayer());
    h.landOnBar();
    h.update(makePlayer(2));
    const canceled = s.transferSerial;
    assert.equal(s.moving, true);
    h.fullscreen(true);
    assert.equal(s.moving, false);
    assert.equal(s.owner, "toast");
    assert.equal(s.toastMapped, true);
    assert.equal(s.ownsView("bar"), false);
    h.update(makePlayer(3));
    s.finishTransfer(canceled);
    assert.equal(s.owner, "toast");
    assert.equal(s.toastView.targetTrack.title, "Track 3");
    assert.equal(s.toastMapped, true);
});

test("fullscreen popup opens and closes without flying through the hidden bar", () => {
    const h = makeService();
    const s = h.service;
    h.fullscreen(true);
    h.update(makePlayer());
    s.dismissToast();
    s.finishToastExit();
    s.setPopupOpen(true);
    assert.equal(s.popupMapped, true);
    assert.equal(s.ownsView("popup"), true);
    assert.equal(s.moving, false);
    s.setPopupOpen(false);
    assert.equal(s.popupMapped, false);
    assert.equal(s.ownsView("bar"), false);
    assert.equal(s.barView.displayedTrack.title, "Track 1");
    assert.equal(h.transfers.length, 0);
    h.fullscreen(false);
    assert.equal(s.ownsView("bar"), true);
    h.update(makePlayer(2));
    assert.equal(s.moving, true, "ordinary transfers resume when the bar is visible");
    assert.equal(s.transferFrom, "bar");
    assert.equal(s.transferTo, "toast");
});
