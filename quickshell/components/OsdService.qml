pragma Singleton

import QtQuick

// Lets in-shell controls identify changes that should not produce duplicate
// feedback. Hardware keys and changes from external clients remain visible.
QtObject {
    property double volumeSuppressedUntil: 0
    property double brightnessSuppressedUntil: 0
    property bool controlCenterOpen: false
    // Toasts share the same attached corner and wait for feedback to finish.
    property bool overlayVisible: false

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
