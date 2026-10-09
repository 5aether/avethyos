pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// Native BlueZ models keep device, battery and adapter state current. Only a
// user action starts bluetoothctl, with a separate bounded job per device.
QtObject {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool powered: !!adapter && adapter.enabled
    readonly property bool scanning: !!adapter && adapter.discovering
    readonly property string adapterName: adapter ? adapter.name : "No Bluetooth adapter"
    readonly property bool blocked: !!adapter && adapter.state === BluetoothAdapterState.Blocked
    readonly property var known: Bluetooth.devices.values.map(function(device) {
        return root.decorate(device);
    }).sort(function(a, b) { return a.name.localeCompare(b.name); })
    readonly property var pairedDevices: known.filter(function(device) { return device.paired; })
    readonly property var connectedDevices: known.filter(function(device) { return device.connected; })
    readonly property var savedDevices: known.filter(function(device) { return device.paired && !device.connected; })
    readonly property var discoveredDevices: known.filter(function(device) { return !device.paired && !device.connected; })
    readonly property var pairedAddresses: addressMap(pairedDevices)
    readonly property var connectedAddresses: addressMap(connectedDevices)
    readonly property bool connected: connectedDevices.length > 0
    // Kept for existing status widgets. New menus use the independent jobs map.
    readonly property string busyAddress: Object.keys(actions)[0] || ""
    readonly property string actionKind: busyAddress ? actions[busyAddress].phase : ""
    property var actions: ({})
    property var deviceErrors: ({})
    property var jobs: ({})
    property string message: ""
    property bool messageIsError: false
    property bool powerBusy: false
    property bool powerTarget: false
    property bool scanRequested: false
    readonly property string actionHelper: Qt.resolvedUrl("../scripts/bluetooth-action.py").toString().replace(/^file:\/\//, "")

    function addressMap(devices) {
        const result = {};
        devices.forEach(device => { result[device.address] = true; });
        return result;
    }

    function decorate(device) {
        return {
            address: device.address,
            name: device.name || device.deviceName || device.address,
            paired: device.paired,
            connected: device.connected,
            pairing: device.pairing,
            trusted: device.trusted,
            blocked: device.blocked,
            battery: device.batteryAvailable ? Math.round(device.battery * 100) : -1,
            icon: device.icon,
            nativeDevice: device
        };
    }

    function iconFor(device) {
        const icon = String(device.icon || "").toLowerCase();
        if (/headset|headphone/.test(icon)) return "headphones";
        if (/audio|speaker/.test(icon)) return "speaker";
        if (/keyboard/.test(icon)) return "keyboard";
        if (/mouse/.test(icon)) return "mouse";
        if (/phone/.test(icon)) return "smartphone";
        if (/computer/.test(icon)) return "computer";
        if (/game|input-gaming/.test(icon)) return "sports_esports";
        return "bluetooth";
    }

    function report(text, error) {
        message = text;
        messageIsError = error === true;
    }

    function clearMessage() { message = ""; }
    // Native object models update from D-Bus signals, so refresh does not poll.
    function refresh() { if (blocked) report("Bluetooth is blocked by the hardware switch.", true); }

    function setPowered(value) {
        if (!adapter || powerBusy) return;
        if (blocked && value) {
            report("Bluetooth is blocked. Turn off airplane mode or use the hardware switch.", true);
            return;
        }
        if (powered === value) return;
        if (!value) setScanning(false);
        clearMessage();
        powerTarget = value;
        powerBusy = true;
        powerWatch.restart();
        adapter.enabled = value;
    }

    function setScanning(value) {
        if (!adapter || (value && !powered)) return;
        scanRequested = value;
        scanWatch.stop();
        if (value) {
            clearMessage();
            scanLimit.restart();
            scanWatch.restart();
        } else {
            scanLimit.stop();
        }
        adapter.discovering = value;
    }

    function patchAction(address, patch) {
        const next = Object.assign({}, actions);
        next[address] = Object.assign({}, next[address] || {}, patch);
        actions = next;
    }

    function clearDeviceError(address) {
        const next = Object.assign({}, deviceErrors);
        delete next[address];
        deviceErrors = next;
    }

    function runAction(device, kind) {
        if (!device || !/^[0-9A-F:]{17}$/i.test(device.address) || jobs[device.address]) return;
        if (kind !== "remove" && !powered) return;
        clearDeviceError(device.address);
        clearMessage();
        const job = actionFactory.createObject(root, {
            address: device.address, deviceName: device.name,
            kind: kind, nativeDevice: device.nativeDevice || null
        });
        if (!job) {
            report("Could not start the Bluetooth action.", true);
            return;
        }
        const next = Object.assign({}, jobs);
        next[device.address] = job;
        jobs = next;
        patchAction(device.address, { phase: kind, prompt: null });
        job.running = true;
    }

    function activate(device) {
        if (device) runAction(device, device.connected ? "disconnect" : device.paired ? "connect" : "pair");
    }
    function connectDevice(device) { runAction(device, device.paired ? "connect" : "pair"); }
    function disconnectDevice(device) { runAction(device, "disconnect"); }
    function forget(device) { runAction(device, "remove"); }

    function answerPairing(address, answer) {
        const job = jobs[address];
        if (!job || !actions[address] || !actions[address].prompt) return;
        const prompt = actions[address].prompt;
        const value = String(answer);
        if (prompt.kind === "passkey" && !/^[0-9]{1,6}$/.test(value)) {
            report("Enter a passkey using one to six digits.", true);
            return;
        }
        if (prompt.kind === "pin" && (!value.length || value.length > 16 || /[\x00-\x1f\x7f]/.test(value))) {
            report("Enter a PIN using one to sixteen characters.", true);
            return;
        }
        job.write(JSON.stringify({ answer: value }) + "\n");
        patchAction(address, { prompt: null });
    }

    function cancelAction(address) {
        const job = jobs[address];
        if (!job) return;
        job.cancelled = true;
        if (job.nativeDevice && job.nativeDevice.pairing) job.nativeDevice.cancelPair();
        job.running = false;
    }

    function receiveAction(job, line) {
        let event;
        try { event = JSON.parse(line); } catch (_) { return; }
        if (event.event === "phase") {
            patchAction(job.address, { phase: event.phase, prompt: null });
        } else if (event.event === "prompt") {
            patchAction(job.address, { prompt: event });
        } else if (event.event === "result") {
            job.resultReceived = true;
            job.succeeded = event.success === true;
            job.failure = event.error || "";
        }
    }

    function finishAction(job, exitCode) {
        const nextActions = Object.assign({}, actions);
        const nextJobs = Object.assign({}, jobs);
        delete nextActions[job.address];
        delete nextJobs[job.address];
        actions = nextActions;
        jobs = nextJobs;
        if (job.cancelled) {
            report("Cancelled the action for " + job.deviceName + ".", false);
        } else if (exitCode !== 0 || !job.succeeded) {
            const error = job.failure || "Bluetooth action failed. Check the device is awake and try again.";
            const nextErrors = Object.assign({}, deviceErrors);
            nextErrors[job.address] = error;
            deviceErrors = nextErrors;
            report(job.deviceName + ": " + error, true);
        } else {
            const verb = job.kind === "remove" ? "Forgot " : job.kind === "disconnect" ? "Disconnected " : "Connected ";
            report(verb + job.deviceName + ".", false);
        }
        Qt.callLater(function() { job.destroy(); });
    }

    property Connections adapterChanges: Connections {
        target: root.adapter
        function onEnabledChanged() {
            if (root.powerBusy && root.powered === root.powerTarget) {
                root.powerBusy = false;
                powerWatch.stop();
            }
            if (!root.powered) {
                root.scanRequested = false;
                scanLimit.stop();
                scanWatch.stop();
            }
        }
        function onDiscoveringChanged() {
            if (root.scanning) scanWatch.stop();
        }
    }
    property Timer powerWatch: Timer {
        interval: 4000
        onTriggered: {
            root.powerBusy = false;
            if (root.powered !== root.powerTarget)
                root.report("Could not change Bluetooth power. Check airplane mode or the hardware switch.", true);
        }
    }
    property Timer scanWatch: Timer {
        interval: 2000
        onTriggered: {
            if (root.scanRequested && !root.scanning) {
                root.scanRequested = false;
                scanLimit.stop();
                root.report("Could not start discovery. Check Bluetooth power and try again.", true);
            }
        }
    }
    property Timer scanLimit: Timer {
        interval: 20000
        onTriggered: {
            root.setScanning(false);
            root.report("Discovery finished. Scan again to find more devices.", false);
        }
    }
    property Component actionFactory: Component {
        Process {
            id: job
            required property string address
            required property string deviceName
            required property string kind
            property var nativeDevice: null
            property bool cancelled: false
            property bool resultReceived: false
            property bool succeeded: false
            property string failure: ""
            command: ["python3", root.actionHelper, kind, address]
            stdinEnabled: true
            stdout: SplitParser { onRead: line => root.receiveAction(job, line) }
            stderr: StdioCollector {
                onStreamFinished: if (text.trim() && !job.failure) job.failure = text.trim();
            }
            onExited: function(exitCode) { root.finishAction(job, exitCode); }
        }
    }
}
