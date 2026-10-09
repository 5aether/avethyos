const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const src = fs.readFileSync(
    path.join(__dirname, "..", "modules", "appSearch.js"), "utf8");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src, ctx);

const apps = [
    { id: "zeta.desktop", name: "Zeta Editor", genericName: "Text Editor", keywords: [] },
    { id: "kitty.desktop", name: "Kitty", genericName: "Terminal", keywords: ["shell"] },
    { id: "alacritty.desktop", name: "Alacritty", genericName: "Terminal", keywords: [] },
    { id: "firefox.desktop", name: "Firefox", genericName: "Browser", keywords: ["web"] }
];

test("unused applications are sorted alphabetically", () => {
    assert.deepStrictEqual(
        Array.from(ctx.rankApps(apps, "", {}), app => app.name),
        ["Alacritty", "Firefox", "Kitty", "Zeta Editor"]);
});

test("used applications lead by descending launch count", () => {
    const usage = { "kitty.desktop": 44, "alacritty.desktop": 12 };
    assert.deepStrictEqual(
        Array.from(ctx.rankApps(apps, "", usage), app => app.name),
        ["Kitty", "Alacritty", "Firefox", "Zeta Editor"]);
});

const wallpaperApps = [
    { id: "openwallpaper.desktop", name: "OpenWallpaper", keywords: ["wallpaper"] },
    { id: "waterfox.desktop", name: "Waterfox", genericName: "Web Browser" },
    { id: "wallpaper.desktop", name: "Wallpaper" }
];

test("search matches substrings in names and metadata", () => {
    assert.deepStrictEqual(
        Array.from(ctx.rankApps(wallpaperApps, "wa", { "openwallpaper.desktop": 100 }), app => app.name),
        ["OpenWallpaper", "Wallpaper", "Waterfox"]);
    assert.strictEqual(ctx.rankApps(apps, "kty", {}).length, 0);
    for (const [query, expected] of [
        ["web", ["Firefox"]], ["terminal", ["Alacritty", "Kitty"]],
        ["editor", ["Zeta Editor"]], ["shell", ["Kitty"]]
    ]) {
        assert.deepStrictEqual(
            Array.from(ctx.rankApps(apps, query, {}), app => app.name), expected);
    }
});

test("launch history takes priority among metadata matches on the next search", () => {
    const usage = {};
    assert.strictEqual(ctx.rankApps(wallpaperApps, "wa", usage)[0].name, "OpenWallpaper");
    usage["waterfox.desktop"] = 1;
    assert.deepStrictEqual(
        Array.from(ctx.rankApps(wallpaperApps, "wa", usage), app => app.name),
        ["Waterfox", "OpenWallpaper", "Wallpaper"]);
});

test("matching ignores case and surrounding query whitespace", () => {
    assert.deepStrictEqual(
        Array.from(ctx.rankApps(wallpaperApps, "  WA  ", {}), app => app.name),
        ["OpenWallpaper", "Wallpaper", "Waterfox"]);
});

test("equal launch counts use alphabetical order and do not reorder the source", () => {
    const original = wallpaperApps.slice();
    assert.deepStrictEqual(
        Array.from(ctx.rankApps(wallpaperApps, "wa", {
            "waterfox.desktop": 2, "wallpaper.desktop": 2
        }), app => app.name),
        ["Wallpaper", "Waterfox", "OpenWallpaper"]);
    assert.deepStrictEqual(wallpaperApps, original);
});

test("Discord finds Vesktop through its description or keywords", () => {
    for (const fields of [
        { comment: "Vesktop is a custom Discord desktop app" },
        { description: "Discord client" },
        { keywords: ["discord", "chat"] }
    ]) {
        const entry = Object.assign({ id: "vesktop", name: "Vesktop" }, fields);
        assert.strictEqual(ctx.rankApps([entry], "DISCORD", {})[0], entry);
    }
});

test("search covers identifiers, commands, categories and custom file values", () => {
    const entry = { id: "org.example.Vesktop.desktop", name: "Vesktop",
        execString: "/opt/vesktop-client %U", categories: ["Network"],
        startupClass: "chat-window", icon: "messenger-icon", workingDirectory: "/opt/chat" };
    const index = { "org.example.Vesktop": "Discord client\napplication/x-chat\nNuova finestra\ncustom-tag" };
    for (const query of ["example", "vesktop-client", "network", "chat-window",
        "messenger-icon", "/opt/chat", "discord", "application/x-chat", "nuova", "custom-tag"]) {
        assert.strictEqual(ctx.rankApps([entry], query, {}, index)[0], entry);
    }
    assert.strictEqual(ctx.rankApps([entry], "vesktop discord network", {}, index)[0], entry);
    assert.strictEqual(ctx.rankApps([entry], "discord missing", {}, index).length, 0);
});

test("missing optional fields are harmless and whitespace shows all apps", () => {
    const entry = { name: "Minimal" };
    assert.strictEqual(ctx.rankApps([entry], "minimal", {})[0], entry);
    assert.strictEqual(ctx.rankApps([entry], "undefined", {}).length, 0);
    assert.strictEqual(ctx.rankApps(apps, " \t ", {}).length, apps.length);
});
