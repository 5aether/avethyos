const test = require("node:test");
const assert = require("node:assert/strict");
const { luminance, readableAccent } = require("../modules/mediaColors.js");

test("cover accents meet text contrast on the brightest tinted artwork", () => {
    const backdrop = luminance([0.33, 0.32, 0.35]);
    for (const seed of ["#000000", "#320021", "#007800", "#101080", "#995511", "#eeddff", "#ffffff", "invalid"]) {
        const accent = readableAccent(seed);
        assert.match(accent, /^#[0-9a-f]{6}$/);
        const channels = [1, 3, 5].map(index => parseInt(accent.slice(index, index + 2), 16) / 255);
        assert.ok((luminance(channels) + 0.05) / (backdrop + 0.05) >= 4.5, seed);
    }
});

test("readable accents retain their color and darker ones keep channel order", () => {
    assert.equal(readableAccent("#eeddff"), "#eeddff");
    const accent = readableAccent("#a02060");
    const rgb = [1, 3, 5].map(index => parseInt(accent.slice(index, index + 2), 16));
    assert.ok(rgb[0] > rgb[2] && rgb[2] > rgb[1]);
});
