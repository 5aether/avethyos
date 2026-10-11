const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "bar", "ControlCenter.qml"), "utf8");

// Run the production JavaScript with controlled process completions. These
// tests do not issue DDC/CI writes or require more than one physical monitor.
function blockAt(opening) {
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
        } else if (ch === "\"" || ch === "'") {
            quote = ch;
        } else if (ch === "{") {
            ++depth;
        } else if (ch === "}" && --depth === 0) {
            return source.slice(opening, i + 1);
        }
    }
    throw new Error("Unclosed production QML block");
}

function makeControlCenter() {
    const deferred = [];
    const state = vm.createContext({
        brightness: -1,
        brightnessByDisplay: {},
        brightnessRevisions: {},
        pendingBrightnessWrites: [],
        brightnessRefreshPending: false,
        popupOpen: false,
        popupMotion: { progress: 0 },
        brightnessRefreshTimer: { starts: 0, restart() { ++this.starts; } },
        monitors: [],
        selectedDisplay: 1,
        brightnessQuery: { running: false, display: 1, revision: 0, output: "" },
        brightnessWrite: { running: false, display: 1, level: 0 },
        OsdService: { suppressBrightness() {} },
        Qt: { callLater(fn) { deferred.push(fn); } },
    });
    state.root = state;
    for (const name of ["brightnessRevision", "rememberBrightness", "moveBrightness",
        "requestBrightness", "finishBrightnessRead", "commitBrightness", "continueBrightnessWork",
        "refresh", "brightnessTarget"]) {
        const start = source.indexOf("    function " + name + "(");
        assert.notEqual(start, -1, `Missing production function ${name}`);
        const opening = source.indexOf("{", start);
        vm.runInContext(source.slice(start, opening) + blockAt(opening), state);
    }
    const selectionAt = source.indexOf("onSelectedDisplayChanged:");
    assert.notEqual(selectionAt, -1);
    const selectionChanged = vm.runInContext("(function() "
        + blockAt(source.indexOf("{", selectionAt)) + ")", state);
    return {
        state,
        select(display) {
            state.selectedDisplay = display;
            selectionChanged();
        },
        flush() { while (deferred.length) deferred.shift()(); },
        read(output, exitCode = 0) {
            assert.equal(state.brightnessQuery.running, true);
            state.brightnessQuery.output = output;
            state.brightnessQuery.running = false;
            state.finishBrightnessRead(exitCode);
            this.flush();
        },
        wrote() {
            assert.equal(state.brightnessWrite.running, true);
            state.brightnessWrite.running = false;
            // Execute the actual Process exit handler.
            const start = source.indexOf("id: brightnessWrite");
            const handler = source.slice(start).match(/^        onExited: (.+)$/m)[1];
            vm.runInContext(handler, state);
            this.flush();
        },
    };
}

test("opening shows the cached brightness before scheduling a hardware refresh", () => {
    const s = makeControlCenter().state;
    s.rememberBrightness(1, 65, 100);
    s.popupOpen = true;
    s.refresh();
    assert.equal(s.brightnessRefreshTimer.starts, 0);
    assert.equal(s.brightnessQuery.running, false);
    assert.equal(s.brightness, 65);
    s.popupMotion.progress = 1;
    s.refresh();
    assert.equal(s.brightnessRefreshTimer.starts, 1);
    assert.equal(s.brightnessQuery.running, false, "the timer defers the query until after painting");
    s.popupOpen = false;
    s.refresh();
    assert.equal(s.brightnessRefreshTimer.starts, 1, "closed popups do not schedule reads");
});

test("brightness targets the detected I2C bus with a display-number fallback", () => {
    const s = makeControlCenter().state;
    s.monitors = [{ id: 1, bus: 2 }, { id: 2, bus: 4 }, { id: 3, bus: -1 }];
    assert.deepEqual(Array.from(s.brightnessTarget(1)), ["--bus", "2"]);
    assert.deepEqual(Array.from(s.brightnessTarget(2)), ["--bus", "4"]);
    assert.deepEqual(Array.from(s.brightnessTarget(3)), ["--display", "3"]);
    assert.deepEqual(Array.from(s.brightnessTarget(9)), ["--display", "9"]);
});

test("changing displays during a read queues the new target and keeps results with their monitor", () => {
    const h = makeControlCenter();
    const s = h.state;
    s.requestBrightness();
    h.select(2);
    assert.equal(s.brightness, -1);
    assert.equal(s.brightnessQuery.display, 1, "the running query keeps its original target");
    h.read("VCP 10 C 23 100");
    assert.equal(s.brightness, -1, "display 1's result cannot become display 2's slider value");
    assert.equal(s.brightnessByDisplay[1].level, 23);
    assert.equal(s.brightnessQuery.display, 2);
    h.read("VCP 10 C 81 100");
    assert.equal(s.brightness, 81);
    h.select(1);
    assert.equal(s.brightness, 23, "switching back immediately restores that monitor's own level");
});

test("rapid selection changes read the latest selected monitor", () => {
    const h = makeControlCenter();
    h.state.requestBrightness();
    h.select(2);
    h.select(3);
    h.read("VCP 10 C 15 100");
    assert.equal(h.state.brightnessQuery.display, 3);
    h.read("VCP 10 C 95 100");
    assert.equal(h.state.brightness, 95);
});

test("a read started before a slider edit cannot replace the new level", () => {
    const h = makeControlCenter();
    const s = h.state;
    s.requestBrightness();
    s.moveBrightness(64);
    s.commitBrightness(64);
    assert.equal(s.brightnessWrite.running, false, "serialize reads and writes");
    h.read("VCP 10 C 23 100");
    assert.equal(s.brightness, 64);
    assert.equal(s.brightnessWrite.display, 1);
    assert.equal(s.brightnessWrite.level, 64);
    h.wrote();
    assert.equal(s.brightnessQuery.running, true);
    h.read("VCP 10 C 64 100");
    assert.equal(s.brightness, 64);
});

test("switching away and back during a write waits for the updated hardware value", () => {
    const h = makeControlCenter();
    const s = h.state;
    s.requestBrightness();
    h.read("VCP 10 C 20 100");
    s.moveBrightness(62);
    s.commitBrightness(62);
    h.select(2);
    h.select(1);
    assert.equal(s.brightness, 62);
    assert.equal(s.brightnessQuery.running, false, "do not read until the pending write completes");
    h.wrote();
    assert.equal(s.brightnessQuery.display, 1);
    h.read("VCP 10 C 62 100");
    assert.equal(s.brightness, 62);
});

test("a failed read for the previous monitor cannot clear the selected monitor's slider", () => {
    const h = makeControlCenter();
    const s = h.state;
    s.rememberBrightness(2, 70, 100);
    s.requestBrightness();
    h.select(2);
    h.read("", 1);
    assert.equal(s.brightness, 70);
    assert.equal(s.brightnessByDisplay[1].level, -1);
    assert.equal(s.brightnessQuery.display, 2);
});

test("writes use the selected monitor's reported VCP maximum", () => {
    const h = makeControlCenter();
    const s = h.state;
    s.requestBrightness();
    h.read("VCP 10 C 75 250");
    assert.equal(s.brightness, 30);
    s.moveBrightness(40);
    s.commitBrightness(40);
    assert.equal(s.brightnessWrite.level, 100);
});

test("queued edits coalesce per monitor and retain writes for other selected monitors", () => {
    const h = makeControlCenter();
    const s = h.state;
    s.requestBrightness();
    s.moveBrightness(40);
    s.commitBrightness(40);
    s.moveBrightness(55);
    s.commitBrightness(55);
    h.select(2);
    s.moveBrightness(80);
    s.commitBrightness(80);
    assert.equal(s.pendingBrightnessWrites.length, 2);
    h.read("VCP 10 C 20 100");
    assert.equal(s.brightnessWrite.display, 1);
    assert.equal(s.brightnessWrite.level, 55);
    assert.equal(s.brightness, 80);
    h.wrote();
    assert.equal(s.brightnessWrite.display, 2);
    assert.equal(s.brightnessWrite.level, 80);
    h.wrote();
    assert.equal(s.brightnessQuery.display, 2);
    h.read("VCP 10 C 80 100");
    assert.equal(s.brightness, 80);
});
