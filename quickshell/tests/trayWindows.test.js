const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, "../modules/trayWindows.js"), "utf8"), ctx);
const { findWindow } = ctx;

test("matches Electron tray IDs and reverse-domain window classes", () => {
    const vesktop = { address: "0x1", class: "vesktop" };
    const whatsie = { address: "0x2", class: "com.ktechpit.whatsie" };
    assert.equal(findWindow({ id: "appindicator-vesktop-1243" }, [vesktop, whatsie]), vesktop);
    assert.equal(findWindow({ title: "Whatsie" }, [vesktop, whatsie]), whatsie);
});

test("uses initial class when the current class changes", () => {
    const app = { address: "0x1", class: "dialog", initialClass: "feishin" };
    assert.equal(findWindow({ tooltipTitle: "Feishin" }, [app]), app);
});

test("prefers the app's most recently focused window", () => {
    const old = { address: "0x1", class: "vesktop", focusHistoryID: 5 };
    const recent = { address: "0x2", class: "vesktop", focusHistoryID: 1 };
    assert.equal(findWindow({ id: "vesktop" }, [old, recent]), recent);
});

test("does not focus unrelated document titles or partial class matches", () => {
    const clients = [
        { address: "0x1", class: "kitty", title: "Feishin configuration" },
        { address: "0x2", class: "feishin-helper" },
        { address: "0x3", class: "feishin", mapped: false }
    ];
    assert.equal(findWindow({ id: "feishin" }, clients), null);
    assert.equal(findWindow({}, clients), null);
    assert.equal(findWindow({ id: "feishin" }, []), null);
});
