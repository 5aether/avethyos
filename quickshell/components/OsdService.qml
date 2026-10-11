pragma Singleton

import QtQuick

// Lets in-shell controls identify changes that should not produce duplicate
// feedback. Hardware keys and changes from external clients remain visible.
QtObject {
    property double volumeSuppressedUntil: 0
    property double brightnessSuppressedUntil: 0
    property var openControlCenters: []
    readonly property bool controlCenterOpen: openControlCenters.length > 0
    // Toasts share the same attached corner and wait for feedback to finish.
    property bool overlayVisible: false

    function setControlCenterOpen(control, opened) {
        const others = openControlCenters.filter(candidate => candidate !== control);
        openControlCenters = opened ? others.concat([control]) : others;
    }

    function suppressVolume() {
        volumeSuppressedUntil = Date.now() + 750;
    }

    function suppressBrightness() {
        brightnessSuppressedUntil = Date.now() + 750;
    }

    function volumeAllowed() {
        return !controlCenterOpen && Date.now() >= volumeSuppressedUntil;
    }

    function brightnessAllowed() {
        return !controlCenterOpen && Date.now() >= brightnessSuppressedUntil;
    }
}
