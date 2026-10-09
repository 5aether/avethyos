import QtQuick
import Quickshell.Hyprland

// PopupWindow's native grab needs a Wayland input serial, which an IPC call
// cannot provide. Hyprland's focus-grab protocol works for both pointer opens
// and programmatic opens while retaining outside-click dismissal.
//
// This component enables click-outside-to-close behavior: clicking anywhere
// outside the popup (including on the desktop or other windows) will close it.
HyprlandFocusGrab {
    id: root
    required property var popupWindow
    property bool opened: popupWindow ? popupWindow.visible : false
    property var extraWindows: []
    // Some nested popups (such as a system-tray menu inside the control
    // center) should be dismissed before their parent popup.
    property bool dismissExtraWindowsFirst: false
    property bool rearming: false
    property var dismissAction: null
    signal dismissed()
    signal extraWindowsDismissed()

    function preservePopupOnNextClear(): void {
        // Changing the set of grabbed windows (for example, hiding a tray
        // menu) makes Hyprland clear the current grab asynchronously. Disarm
        // first and only create the replacement grab after that update has
        // settled, so its cleared signal cannot dismiss the parent popup.
        rearming = true;
        rearmTimer.restart();
    }

    property Timer rearmTimer: Timer {
        id: rearmTimer
        interval: 250
        onTriggered: root.rearming = false
    }

    windows: popupWindow ? [popupWindow].concat(extraWindows) : []
    active: popupWindow ? opened && !rearming : false

    onCleared: {
        // Clears received while changing the grabbed window set belong to the
        // internal rearm cycle, not to another click outside the popup.
        if (rearming)
            return;
        if (dismissExtraWindowsFirst && extraWindows.length > 0) {
            preservePopupOnNextClear();
            extraWindowsDismissed();
            return;
        }
        if (dismissAction)
            dismissAction();
        else if (popupWindow)
            popupWindow.visible = false;
        dismissed();
    }
}
