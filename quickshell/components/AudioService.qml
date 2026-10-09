pragma Singleton

import QtQuick
import Quickshell.Services.Pipewire

// Event-driven PipeWire state. No wpctl/pactl subprocesses and no polling.
QtObject {
    id: root

    readonly property var nodes: Pipewire.nodes.values.filter(function(node) {
        return node && node.audio && !node.isStream;
    })
    readonly property var outputs: nodes.filter(function(node) {
        return node.isSink;
    })
    readonly property var output: Pipewire.defaultAudioSink
    // Keep the shell's volume scale at 0–100%, even if an external client
    // sets PipeWire above its normal volume.
    readonly property real volume: output && output.audio
        ? Math.max(0, Math.min(1, output.audio.volume)) : 0
    readonly property bool muted: output && output.audio ? output.audio.muted : false

    function label(node) {
        if (!node)
            return "Unknown device";
        let value = String(node.description || node.nickname || node.name || "Unknown device");
        // Profiles are redundant in a compact device picker.
        value = value.replace(/\s+(?:Analog|Digital)\s+(?:Stereo|Mono|Surround\s+[0-9.]+)\s*$/i, "");
        return value.replace(/\s+/g, " ").trim();
    }

    function setVolume(value) {
        if (output && output.audio)
            output.audio.volume = Math.max(0, Math.min(1, value));
    }

    function setDefaultOutput(node) {
        if (!node)
            return;
        Pipewire.preferredDefaultAudioSink = node;
    }

    property PwObjectTracker tracker: PwObjectTracker {
        objects: root.outputs
    }
}
