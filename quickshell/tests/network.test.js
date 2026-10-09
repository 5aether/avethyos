const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, "../modules/network.js"), "utf8"), context);
const plain = value => JSON.parse(JSON.stringify(value));

test("terse fields preserve escaped SSID colons, backslashes, and empty cells", () => {
    assert.deepEqual(plain(context.fields("*:Studio\\: Wi-Fi\\\\Guest:72:WPA2:wlan0")), ["*", "Studio: Wi-Fi\\Guest", "72", "WPA2", "wlan0"]);
    assert.deepEqual(plain(context.fields("enp2s0:ethernet:disconnected:")), ["enp2s0", "ethernet", "disconnected", ""]);
});

test("simultaneous ethernet ports and virtual links remain independent", () => {
    const devices = plain(context.parseDevices("enp7s0:ethernet:connected:Office\\: wired\nenp2s0:ethernet:connected:Backup\nwg0:wireguard:connected (externally):vpn\nwlan0:wifi:unmanaged:\nlo:loopback:connected (externally):lo\np2p:wifi-p2p:disconnected:\n"));
    assert.deepEqual(devices.map(device => device.device), ["enp2s0", "enp7s0", "wlan0", "wg0"]);
    assert.equal(devices.filter(device => device.connected).length, 3);
    assert.equal(devices[1].connection, "Office: wired");
    assert.equal(devices[2].canControl, false);
    assert.deepEqual(plain(context.deviceCommand("enp2s0", false)), ["nmcli", "--wait", "20", "device", "disconnect", "enp2s0"]);
    assert.deepEqual(plain(context.deviceCommand("enp7s0", true)), ["nmcli", "--wait", "20", "device", "connect", "enp7s0"]);
});

test("detail snapshots preserve IPv6, multiple IPv4 addresses, and MAC colons", () => {
    const details = context.parseDetails("GENERAL.DEVICE:enp7s0\nGENERAL.HWADDR:FC:9D:05:3D:74:7C\nIP4.ADDRESS[1]:192.168.0.55/24\nIP4.ADDRESS[2]:10.0.0.1/8\nIP4.GATEWAY:192.168.0.1\nIP6.ADDRESS[1]:fe80::ced9:abe3:be9d:8c5a/64\n\nGENERAL.DEVICE:enp2s0\nIP4.GATEWAY:\n");
    assert.deepEqual(plain(details.enp7s0), { addresses: ["192.168.0.55/24", "10.0.0.1/8"], ipv6: ["fe80::ced9:abe3:be9d:8c5a/64"], gateway: "192.168.0.1", mac: "FC:9D:05:3D:74:7C" });
    const disconnected = context.parseDevices("enp7s0:ethernet:disconnected:");
    assert.deepEqual(plain(context.mergeDetails(disconnected, details)[0].addresses), []);
});

test("Wi-Fi deduplication retains active APs and distinguishes radios", () => {
    const networks = plain(context.parseNetworks(":Studio\\:Guest:95:WPA2:wlan0\n*:Studio\\:Guest:58:WPA2:wlan0\n:Studio\\:Guest:85:WPA2:wlan1\n:Open:150:--:wlan0\n::30:WPA2:wlan0\n"));
    assert.equal(networks.length, 3);
    assert.equal(networks[0].active, true);
    assert.equal(networks[0].signal, 58);
    assert.equal(networks[0].ssid, "Studio:Guest");
    assert.equal(networks.find(network => network.ssid === "Open").security, "");
    assert.equal(networks.find(network => network.ssid === "Open").signal, 100);
    assert.equal(networks.filter(network => network.ssid === "Studio:Guest").length, 2);
});

test("Wi-Fi command arguments keep shell syntax and passwords literal", () => {
    const network = { ssid: "Office $(touch /tmp/example)", device: "wlan1" };
    assert.deepEqual(plain(context.wifiCommand(network, "p:a'$ss\\word", "wlan0")), ["nmcli", "--wait", "40", "device", "wifi", "connect", network.ssid, "ifname", "wlan1", "password", "p:a'$ss\\word"]);
    assert.deepEqual(plain(context.wifiCommand({ ssid: "Saved network" }, "", "wlan0")), ["nmcli", "--wait", "40", "device", "wifi", "connect", "Saved network", "ifname", "wlan0"]);
});
