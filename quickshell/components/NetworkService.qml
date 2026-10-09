pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/network.js" as Network

// Control and busy state belong to individual devices, including concurrent
// wired links. Every network surface observes the same NetworkManager snapshot.
QtObject {
    id: root

    property bool available: true
    property bool wifiEnabled: false
    property var devices: []
    property var deviceDetails: ({})
    property var wifiNetworks: []
    property var busyDevices: ({})
    property var deviceErrors: ({})
    property string lastError: ""
    property string busySsid: ""

    readonly property var interfaces: devices
    readonly property var connectedDevices: devices.filter(device => device.connected)
    readonly property var connectedInterfaces: connectedDevices
    readonly property int connectedCount: connectedDevices.length
    readonly property var wifiDevices: devices.filter(device => device.type === "wifi")
    readonly property var ethernetDevices: devices.filter(device => device.type === "ethernet")
    readonly property bool hasWifi: wifiDevices.length > 0
    readonly property bool hasManagedWifi: wifiDevices.some(device => device.managed && device.state !== "unavailable")
    readonly property bool scanning: wifiQuery.running || wifiRescan.running
    readonly property bool radioBusy: radioAction.running
    readonly property bool refreshing: radioQuery.running || deviceQuery.running || detailQuery.running
    readonly property bool wifiConnected: wifiDevices.some(device => device.connected)
    readonly property string wifiDevice: preferredDevice(wifiDevices)
    readonly property string connectedSsid: activeSsid()
    readonly property int wifiStrength: activeSignal()
    // Preserve the legacy API consumed by the bar indicator.
    readonly property bool ethernetConnected: ethernetDevices.some(device => device.connected)
    readonly property string ethernetDevice: preferredDevice(ethernetDevices)
    readonly property string ethernetState: deviceByName(ethernetDevice) ? deviceByName(ethernetDevice).state : "Unavailable"
    readonly property string ethernetConnection: deviceByName(ethernetDevice) ? deviceByName(ethernetDevice).connection : ""
    readonly property bool ethernetBusy: ethernetDevices.some(device => !!busyDevices[device.device])

    function fields(line) { return Network.fields(line); }
    function deviceByName(name) { return devices.find(device => device.device === name) || null; }
    function preferredDevice(list) {
        const found = list.find(device => device.connected) || list.find(device => device.canControl) || list[0];
        return found ? found.device : "";
    }
    function activeSsid() {
        const network = wifiNetworks.find(network => network.active && network.device === wifiDevice);
        const device = deviceByName(wifiDevice);
        return network ? network.ssid : device && device.connected ? device.connection : "";
    }
    function activeSignal() {
        const network = wifiNetworks.find(network => network.active && network.device === wifiDevice);
        return network ? network.signal : 0;
    }
    function requestQuery(query) {
        if (query.running) query.pending = true;
        else query.running = true;
    }
    function finishQuery(query) {
        if (!query.pending) return;
        query.pending = false;
        Qt.callLater(function() { root.requestQuery(query); });
    }
    function refresh() {
        requestQuery(radioQuery);
        requestQuery(deviceQuery);
        requestQuery(detailQuery);
        if (wifiEnabled) requestQuery(wifiQuery);
    }
    function clearError() { lastError = ""; }
    function updateDeviceState(output) {
        devices = Network.mergeDetails(Network.parseDevices(output), deviceDetails);
    }
    function setBusy(device, busy, error) {
        const updated = Object.assign({}, busyDevices);
        if (busy) updated[device] = true;
        else delete updated[device];
        busyDevices = updated;
        const errors = Object.assign({}, deviceErrors);
        if (error) errors[device] = error;
        else delete errors[device];
        deviceErrors = errors;
    }
    function runDeviceAction(device, command, ssid) {
        if (!device || busyDevices[device]) return;
        lastError = "";
        setBusy(device, true, "");
        if (ssid) busySsid = ssid;
        const action = deviceAction.createObject(root, { targetDevice: device, targetSsid: ssid || "", command: ["env", "LC_ALL=C"].concat(command) });
        if (!action) {
            setBusy(device, false, "Could not start the network command.");
            lastError = "Could not start the network command.";
            busySsid = "";
            return;
        }
        action.running = true;
    }
    function setDeviceConnected(device, value) {
        const item = deviceByName(device);
        if (!item || !item.canControl || (item.type === "wifi" && !wifiEnabled)) return;
        runDeviceAction(device, Network.deviceCommand(device, value), "");
    }
    function setDeviceManaged(device, value) {
        if (!deviceByName(device)) return;
        runDeviceAction(device, ["nmcli", "device", "set", device, "managed", value ? "yes" : "no"], "");
    }
    function setEthernetConnected(value) { setDeviceConnected(ethernetDevice, value); }
    function setWifiEnabled(value) {
        if (radioAction.running) return;
        lastError = "";
        radioAction.errorOutput = "";
        radioAction.command = ["env", "LC_ALL=C", "nmcli", "radio", "wifi", value ? "on" : "off"];
        radioAction.running = true;
    }
    function scan() {
        if (!wifiEnabled || !hasManagedWifi || scanning) return;
        lastError = "";
        wifiRescan.errorOutput = "";
        wifiRescan.running = true;
    }
    function connectWifi(network, password) {
        if (!network || !network.ssid || !wifiEnabled) return;
        const device = network.device || wifiDevice;
        const item = deviceByName(device);
        if (!item || !item.canControl) return;
        runDeviceAction(device, Network.wifiCommand(network, password, device), network.ssid);
    }
    function disconnectWifi(device) { setDeviceConnected(device || wifiDevice, false); }

    onWifiEnabledChanged: {
        if (wifiEnabled) requestQuery(wifiQuery);
        else wifiNetworks = [];
    }
    Component.onCompleted: refresh()

    property Component deviceAction: Component {
        Process {
            id: action
            property string targetDevice: ""
            property string targetSsid: ""
            property string errorOutput: ""
            stderr: StdioCollector { onStreamFinished: action.errorOutput = text.trim() }
            onExited: function(exitCode) {
                const error = exitCode === 0 ? "" : action.errorOutput || "Network command failed. Try again.";
                root.setBusy(targetDevice, false, error);
                if (error) root.lastError = targetDevice + ": " + error;
                if (root.busySsid === targetSsid) root.busySsid = "";
                // Discard command arguments, which can include a password.
                action.command = [];
                root.refresh();
                action.destroy();
            }
        }
    }
    property Process radioQuery: Process {
        id: radioQuery
        property bool pending: false
        property string output: ""
        command: ["env", "LC_ALL=C", "nmcli", "-t", "-f", "WIFI", "general"]
        stdout: StdioCollector { onStreamFinished: radioQuery.output = text.trim() }
        onExited: function(exitCode) {
            if (exitCode === 0) root.wifiEnabled = output === "enabled";
            root.finishQuery(radioQuery);
        }
    }
    property Process deviceQuery: Process {
        id: deviceQuery
        property bool pending: false
        property string output: ""
        property string errorOutput: ""
        command: ["env", "LC_ALL=C", "nmcli", "-t", "--escape", "yes", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"]
        stdout: StdioCollector { onStreamFinished: deviceQuery.output = text }
        stderr: StdioCollector { onStreamFinished: deviceQuery.errorOutput = text.trim() }
        onExited: function(exitCode) {
            root.available = exitCode === 0;
            if (exitCode === 0) root.updateDeviceState(output);
            else root.lastError = errorOutput || "NetworkManager is unavailable.";
            root.finishQuery(deviceQuery);
        }
    }
    property Process detailQuery: Process {
        id: detailQuery
        property bool pending: false
        property string output: ""
        command: ["env", "LC_ALL=C", "nmcli", "-t", "--escape", "yes", "-f", "GENERAL.DEVICE,GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP6.ADDRESS", "device", "show"]
        stdout: StdioCollector { onStreamFinished: detailQuery.output = text }
        onExited: function(exitCode) {
            if (exitCode === 0) {
                root.deviceDetails = Network.parseDetails(output);
                root.devices = Network.mergeDetails(root.devices, root.deviceDetails);
            }
            root.finishQuery(detailQuery);
        }
    }
    property Process wifiQuery: Process {
        id: wifiQuery
        property bool pending: false
        property string output: ""
        command: ["env", "LC_ALL=C", "nmcli", "-t", "--escape", "yes", "-f", "IN-USE,SSID,SIGNAL,SECURITY,DEVICE", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector { onStreamFinished: wifiQuery.output = text }
        onExited: function(exitCode) {
            if (exitCode === 0 && root.wifiEnabled) root.wifiNetworks = Network.parseNetworks(output);
            root.finishQuery(wifiQuery);
        }
    }
    property Process wifiRescan: Process {
        id: wifiRescan
        property string errorOutput: ""
        command: ["env", "LC_ALL=C", "nmcli", "--wait", "15", "device", "wifi", "rescan"]
        stderr: StdioCollector { onStreamFinished: wifiRescan.errorOutput = text.trim() }
        onExited: function(exitCode) {
            if (exitCode !== 0) root.lastError = errorOutput || "Could not scan for Wi-Fi networks.";
            root.requestQuery(wifiQuery);
        }
    }
    property Process radioAction: Process {
        id: radioAction
        property string errorOutput: ""
        stderr: StdioCollector { onStreamFinished: radioAction.errorOutput = text.trim() }
        onExited: function(exitCode) {
            if (exitCode !== 0) root.lastError = errorOutput || "Could not change Wi-Fi power.";
            root.refresh();
        }
    }
    property Timer refreshDelay: Timer {
        interval: 160
        onTriggered: root.refresh()
    }
    property Timer monitorRetry: Timer {
        interval: 5000
        onTriggered: { if (!monitor.running) monitor.running = true; root.refresh(); }
    }
    property Process monitor: Process {
        id: monitor
        command: ["env", "LC_ALL=C", "nmcli", "monitor"]
        running: true
        stdout: SplitParser { onRead: refreshDelay.restart() }
        onExited: monitorRetry.restart()
    }
}
