const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

// QML .js imports are plain scripts (no module.exports), so evaluate it in a VM.
const src = fs.readFileSync(
    path.join(__dirname, "..", "modules", "format.js"), "utf8");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src, ctx);
const { formatTime } = ctx;

test("formatTime pads hours and minutes", () => {
    assert.strictEqual(formatTime(new Date(2026, 8, 5, 7, 4)), "07:04");
    assert.strictEqual(formatTime(new Date(2026, 8, 5, 23, 59)), "23:59");
});

test("formatTime does not pad single digit minutes differently from two", () => {
    assert.strictEqual(formatTime(new Date(2026, 0, 1, 0, 0)), "00:00");
    assert.strictEqual(formatTime(new Date(2026, 0, 1, 9, 30)), "09:30");
});

test("pad2 left-pads only below ten", () => {
    assert.strictEqual(ctx.pad2(0), "00");
    assert.strictEqual(ctx.pad2(9), "09");
    assert.strictEqual(ctx.pad2(10), "10");
    assert.strictEqual(ctx.pad2(23), "23");
});
