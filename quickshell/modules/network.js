// NetworkManager's terse table format escapes colons and backslashes.
// Keep parsing and command construction independent of QML for verification.
function fields(line) {
    var result = [];
    var field = "";
    var escaped = false;
    for (var i = 0; i < line.length; ++i) {
        var character = line[i];
        if (escaped) { field += character; escaped = false; }
        else if (character === "\\") escaped = true;
        else if (character === ":") { result.push(field); field = ""; }
        else field += character;
    }
    if (escaped) field += "\\";
    result.push(field);
    return result;
}

function parseDevices(text) {
    var devices = [];
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; ++i) {
        var item = fields(lines[i].replace(/\r$/, ""));
        if (item.length < 3 || !item[0] || item[1] === "loopback" || item[1] === "wifi-p2p") continue;
        var state = item[2];
        devices.push({
            device: item[0], type: item[1], state: state,
            connection: item[3] && item[3] !== "--" ? item[3] : "",
            connected: state.indexOf("connected") === 0,
            connecting: state.indexOf("connecting") === 0,
            managed: state !== "unmanaged",
            canControl: state !== "unmanaged" && state !== "unavailable",
            addresses: [], ipv6: [], gateway: "", mac: ""
        });
    }
    devices.sort(function(a, b) {
        var rank = { ethernet: 0, wifi: 1 };
        var aRank = rank[a.type] === undefined ? 2 : rank[a.type];
        var bRank = rank[b.type] === undefined ? 2 : rank[b.type];
        return aRank - bRank || a.device.localeCompare(b.device);
    });
    return devices;
}

function parseDetails(text) {
    var result = {};
    var device = null;
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].replace(/\r$/, "");
        var separator = line.indexOf(":");
        if (separator < 0) continue;
        var key = line.slice(0, separator);
        // Multiline values are not the escaped table format: IPv6 and MAC
        // addresses contain literal colons, so split the key only once.
        var value = line.slice(separator + 1);
        if (key === "GENERAL.DEVICE") {
            device = { addresses: [], ipv6: [], gateway: "", mac: "" };
            result[value] = device;
        } else if (device) {
            if (key.indexOf("IP4.ADDRESS") === 0 && value) device.addresses.push(value);
            else if (key.indexOf("IP6.ADDRESS") === 0 && value) device.ipv6.push(value);
            else if (key === "IP4.GATEWAY") device.gateway = value;
            else if (key === "GENERAL.HWADDR") device.mac = value;
        }
    }
    return result;
}

function mergeDetails(devices, details) {
    return devices.map(function(device) {
        var item = {};
        Object.keys(device).forEach(function(key) { item[key] = device[key]; });
        var detail = details[device.device];
        // Older details must not restore addresses on a disconnected link.
        item.addresses = device.connected && detail ? detail.addresses : [];
        item.ipv6 = device.connected && detail ? detail.ipv6 : [];
        item.gateway = device.connected && detail ? detail.gateway : "";
        item.mac = detail ? detail.mac : "";
        return item;
    });
}

function parseNetworks(text) {
    var result = [];
    var seen = {};
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; ++i) {
        var item = fields(lines[i].replace(/\r$/, ""));
        if (item.length < 4 || !item[1]) continue;
        var network = {
            ssid: item[1], signal: Math.max(0, Math.min(100, Number(item[2]) || 0)),
            security: item[3] === "--" ? "" : item[3], active: item[0] === "*",
            device: item[4] || ""
        };
        var key = JSON.stringify([network.device, network.ssid]);
        var index = seen[key];
        if (index !== undefined) {
            var previous = result[index];
            // Deduplicating access points must retain the active access point.
            if (network.active || (!previous.active && network.signal > previous.signal)) result[index] = network;
        } else {
            seen[key] = result.length;
            result.push(network);
        }
    }
    result.sort(function(a, b) {
        return Number(b.active) - Number(a.active) || b.signal - a.signal || a.ssid.localeCompare(b.ssid);
    });
    return result;
}

function deviceCommand(device, connected) {
    return ["nmcli", "--wait", "20", "device", connected ? "connect" : "disconnect", device];
}

function wifiCommand(network, password, fallbackDevice) {
    var command = ["nmcli", "--wait", "40", "device", "wifi", "connect", network.ssid];
    var device = network.device || fallbackDevice;
    if (device) command.push("ifname", device);
    if (password) command.push("password", password);
    return command;
}

function deviceLabel(type) {
    var labels = { ethernet: "Ethernet", wifi: "Wi-Fi", bridge: "Bridge", bond: "Bond", vlan: "VLAN", wireguard: "WireGuard", tun: "Tunnel", gsm: "Mobile data", bluetooth: "Bluetooth network" };
    return labels[type] || type;
}

function stateLabel(device, wifiEnabled) {
    if (device.type === "wifi" && !wifiEnabled) return "Wi-Fi is off";
    if (!device.managed) return "Not managed by NetworkManager";
    if (device.connected) return "Connected";
    if (device.connecting) return "Connecting…";
    if (device.state === "unavailable") return device.type === "ethernet" ? "Cable unplugged" : "Unavailable";
    if (device.state === "disconnected") return "Disconnected";
    return device.state ? device.state[0].toUpperCase() + device.state.slice(1) : "Unavailable";
}
