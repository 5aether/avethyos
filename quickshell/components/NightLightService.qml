pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The helper owns a Wayland CTM connection, not a captured screen shader.
// Quickshell closes the connection on exit/reload, restoring neutral colors.
QtObject {
    id: root

    property bool available: false
    property bool probeComplete: false
    property bool active: false
    property bool ready: false
    property bool requestInFlight: false
    property string error: ""
    readonly property bool retrying: requestInFlight || retryTimer.running
    readonly property string helperPath: Qt.resolvedUrl("../scripts/night-light.py").toString().replace(/^file:\/\//, "")

    function setEnabled(value) { Config.setNightLight(value); }
    function setTemperature(value) { Config.setNightLightTemperature(value); }

    function applyConfig() {
        if (!ready || !backend.running)
            return;
        retryTimer.stop();
        requestInFlight = true;
        backend.write(JSON.stringify({ enabled: Config.nightLightEnabled,
            temperature: Config.nightLightTemperature }) + "\n");
    }

    function receiveStatus(data) {
        let status;
        try { status = JSON.parse(data); }
        catch (_) { return; }

        available = status.available;
        probeComplete = true;
        active = status.active;
        error = status.error || "";
        if (status.event === "ready") {
            ready = true;
            applyConfig();
        } else {
            requestInFlight = false;
            if (available && Config.nightLightEnabled && !active)
                retryTimer.restart();
        }
    }

    property Process backend: Process {
        command: ["python3", root.helperPath].concat(Hyprland.usingLua ? ["--lua"] : [])
        stdinEnabled: true
        stdout: SplitParser { onRead: data => root.receiveStatus(data) }
        onExited: {
            root.ready = false;
            root.active = false;
            root.requestInFlight = false;
            root.probeComplete = true;
            // Reconnect after a compositor restart or transient socket failure.
            retryTimer.restart();
        }
    }

    property Timer retryTimer: Timer {
        interval: 3000
        onTriggered: {
            if (backend.running)
                root.applyConfig();
            else
                backend.running = true;
        }
    }

    property Connections configConnection: Connections {
        target: Config
        function onNightLightEnabledChanged() { root.applyConfig(); }
        function onNightLightTemperatureChanged() {
            if (Config.nightLightEnabled)
                root.applyConfig();
        }
    }

    Component.onCompleted: backend.running = true
}
