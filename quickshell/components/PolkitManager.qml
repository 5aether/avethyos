pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Polkit

// Single PolkitAgent instance for the whole shell. Exactly one agent should be
// registered with polkitd at a time, so every part of the bar reads this object
// instead of instantiating its own.
QtObject {
    id: root

    property PolkitAgent agent: PolkitAgent {
        id: polkitAgent
    }

    readonly property bool registered: agent.isRegistered
    readonly property bool active: agent.isActive
    readonly property var flow: agent.flow

    // True while a request is pending and the user has not finished it.
    readonly property bool pending: active && flow !== null
        && !flow.isCompleted && !flow.isCancelled

    readonly property bool failed: pending && flow.failed

    function submit(password) {
        if (pending)
            flow.submit(password);
    }

    function cancel() {
        if (pending)
            flow.cancelAuthenticationRequest();
    }
}
