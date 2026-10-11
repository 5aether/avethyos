const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "modules", "screens.js"), "utf8"), context);
const screenAt = context.screenAt;

test("cursor routing respects monitor boundaries and negative positions", () => {
    const screens = [
        { name: "left", x: -1920, y: 0, width: 1920, height: 1080 },
        { name: "right", x: 0, y: 0, width: 1920, height: 1080 },
    ];
    assert.equal(screenAt({ x: -1, y: 300 }, screens, []), screens[0]);
    assert.equal(screenAt({ x: 0, y: 300 }, screens, []), screens[1]);
    assert.equal(screenAt({ x: 1920, y: 300 }, screens, []), null);
    assert.equal(screenAt({ x: 0, y: 1080 }, screens, []), null);
});

test("cursor routing uses compositor geometry for scaled and rotated outputs", () => {
    // Qt can apply its own app scale; compositor coordinates remain definitive.
    const screens = [{ name: "portrait" }, { name: "right" }];
    const monitors = [
        { name: "portrait", x: -1080, y: -200, width: 3840, height: 2160,
            scale: 2, lastIpcObject: { transform: 1 } },
        { name: "right", x: 0, y: 0, width: 2560, height: 1440,
            scale: 1.25, lastIpcObject: { transform: 0 } },
    ];
    assert.equal(screenAt({ x: -1, y: 1700 }, screens, monitors), screens[0]);
    assert.equal(screenAt({ x: -1, y: 1720 }, screens, monitors), null);
    assert.equal(screenAt({ x: 2047, y: 1151 }, screens, monitors), screens[1]);
    assert.equal(screenAt({ x: 2048, y: 1151 }, screens, monitors), null);
    monitors[0].lastIpcObject.transform = 5;
    assert.equal(screenAt({ x: -1, y: 1700 }, screens, monitors), screens[0]);
});

test("disconnected outputs and invalid cursor replies cannot select an output", () => {
    const screens = [{ name: "connected", x: 0, y: 0, width: 1920, height: 1080 }];
    const monitors = [{ name: "disconnected", x: -1920, y: 0, width: 1920, height: 1080, scale: 1 }];
    assert.equal(screenAt({ x: -1, y: 100 }, screens, monitors), null);
    for (const point of [null, {}, { x: NaN, y: 100 }, { x: 100, y: Infinity }])
        assert.equal(screenAt(point, screens, monitors), null);
    assert.equal(screenAt({ x: 100, y: 100 }, [], monitors), null);
});
