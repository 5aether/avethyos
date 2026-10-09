import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../components"
import "../widgets"
Rectangle {
    id: root
    property bool popupOpen: false

    onPopupOpenChanged: {
        OsdService.controlCenterOpen = popupOpen;
        if (!popupOpen) {
            closeToggleMenus();
            controlTray.closeMenus();
            cancelSessionAction();
        }
    }

    function togglePopup(): void {
        const opening = !popupOpen;
        if (opening) {
            devicesOpen = false;
            monitorsOpen = false;
            wallpaperOpen = false;
            bluetoothOpen = false;
            nightLightOpen = false;
            networkOpen = false;
            deviceCloseTimer.stop();
            monitorCloseTimer.stop();
            wallpaperCloseTimer.stop();
            bluetoothCloseTimer.stop();
            nightLightCloseTimer.stop();
            networkCloseTimer.stop();
            deviceLayoutOpen = false;
            monitorLayoutOpen = false;
            wallpaperLayoutOpen = false;
            bluetoothLayoutOpen = false;
            nightLightLayoutOpen = false;
            networkLayoutOpen = false;
        }
        popupOpen = opening;
        if (!opening)
            controlTray.closeMenus();
        if (opening)
            refresh();
    }

    IpcHandler {
        target: "controlcenter"
        function toggle(): void { root.togglePopup(); }
        function close(): void { root.popupOpen = false; }
        function menu(name: string): void {
            if (["network", "bluetooth", "wallpaper", "nightLight"].indexOf(name) < 0) return;
            if (!root.popupOpen) root.togglePopup();
            root.openMenu(name);
        }
    }

    PopupFocus {
        id: popupFocus
        popupWindow: popup
        opened: root.popupOpen
        dismissAction: () => { root.popupOpen = false; }
        onDismissed: controlTray.closeMenus()
    }

    property real volume: AudioService.volume
    // -1 means "unknown": ddcutil is missing or the monitor has no DDC/CI
    // support. The UI shows a dash instead of inventing a percentage.
    property int brightness: -1
    readonly property var outputs: AudioService.outputs
    readonly property int defaultOutput: AudioService.output ? AudioService.output.id : -1
    property bool devicesOpen: false
    property bool deviceLayoutOpen: false
    property bool monitorsOpen: false
    property bool monitorLayoutOpen: false
    property var monitors: []
    // ddcutil display numbering starts at 1. Starting there lets the quick
    // brightness read run in parallel with the slower monitor discovery.
    property int selectedDisplay: 1
    // The shared picker replaces the slider row. Its height follows the
    // visible entries, rather than leaving a large empty panel for one device.
    readonly property int sliderMenuHeight: deviceLayoutOpen
        ? Math.min(330, Math.max(112, 50 + outputs.length * 58))
        : monitorLayoutOpen ? Math.min(330, Math.max(112, 50 + monitors.length * 58)) : 0
    property bool networkOpen: false
    property bool networkLayoutOpen: false
    // Expanded menus use all the space below the header.
    readonly property int networkPanelHeight: Math.min(440, popup.availableHeight - 106)
    readonly property int quickToggleHeight: 298
    property bool wallpaperOpen: false
    property bool wallpaperLayoutOpen: false
    readonly property int wallpaperPanelHeight: Math.min(640, popup.availableHeight - 106)
    property bool bluetoothOpen: false
    property bool bluetoothLayoutOpen: false
    readonly property int bluetoothPanelHeight: Math.min(440, popup.availableHeight - 106)
    property bool nightLightOpen: false
    property bool nightLightLayoutOpen: false
    readonly property int nightLightPanelHeight: Math.min(350, popup.availableHeight - 106)
    readonly property bool toggleMenuOpen: networkOpen || bluetoothOpen
                                        || wallpaperOpen || nightLightOpen
    readonly property bool toggleMenuVisible: networkLayoutOpen || bluetoothLayoutOpen
                                           || wallpaperLayoutOpen || nightLightLayoutOpen
    property var pendingSessionCommand: null
    property bool sessionConfirmationOpen: false
    property string pendingSessionLabel: ""
    property string pendingSessionIcon: ""
    readonly property string trayDate: Qt.formatDate(new Date(), "dddd d MMMM yyyy")

    function openMenu(name) {
        closeToggleMenus();
        devicesOpen = false;
        monitorsOpen = false;
        // Release closing layout slots before switching directly to another menu.
        networkCloseTimer.stop(); bluetoothCloseTimer.stop();
        wallpaperCloseTimer.stop(); nightLightCloseTimer.stop();
        networkLayoutOpen = false; bluetoothLayoutOpen = false;
        wallpaperLayoutOpen = false; nightLightLayoutOpen = false;
        if (name === "network") networkOpen = true;
        else if (name === "bluetooth") bluetoothOpen = true;
        else if (name === "wallpaper") wallpaperOpen = true;
        else if (name === "nightLight") nightLightOpen = true;
        controlTray.closeMenus();
    }

    function closeToggleMenus() {
        networkOpen = false;
        bluetoothOpen = false;
        wallpaperOpen = false;
        nightLightOpen = false;
    }

    function requestSessionAction(command, label, icon) {
        pendingSessionCommand = command;
        pendingSessionLabel = label;
        pendingSessionIcon = icon;
        sessionConfirmationOpen = true;
    }

    function cancelSessionAction() {
        sessionConfirmationOpen = false;
    }

    function confirmSessionAction() {
        if (!pendingSessionCommand)
            return;
        const command = pendingSessionCommand;
        cancelSessionAction();
        popupOpen = false;
        Quickshell.execDetached(command);
    }

    Connections {
        target: AudioService
        function onVolumeChanged() {
            if (!volumeSlider.dragging)
                root.volume = AudioService.volume;
        }
    }
    PopupMotion { id: deviceMotion; opened: root.devicesOpen; attached: false; distance: 24 }
    PopupMotion { id: monitorMotion; opened: root.monitorsOpen; attached: false; distance: 24 }
    PopupMotion { id: wallpaperMotion; opened: root.wallpaperOpen; attached: false; distance: 24 }
    PopupMotion { id: bluetoothMotion; opened: root.bluetoothOpen; attached: false; distance: 24 }
    PopupMotion { id: nightLightMotion; opened: root.nightLightOpen; attached: false; distance: 24 }
    PopupMotion { id: networkMotion; opened: root.networkOpen; attached: false; distance: 24 }
    PopupMotion {
        id: popupMotion
        opened: root.popupOpen
        openDuration: 340
        closeDuration: 230
        distance: panelSurface.height
        horizontalDistance: panelSurface.width
        scaleOnOpen: false
    }
    PopupMotion {
        id: sessionConfirmationMotion
        opened: root.sessionConfirmationOpen
        attached: false
        distance: 14
        onClosed: {
            root.pendingSessionCommand = null;
            root.pendingSessionLabel = "";
            root.pendingSessionIcon = "";
        }
    }

    onDevicesOpenChanged: {
        if (devicesOpen) {
            deviceCloseTimer.stop();
            deviceLayoutOpen = true;
        } else if (deviceLayoutOpen) {
            deviceCloseTimer.restart();
        }
    }
    onMonitorsOpenChanged: {
        if (monitorsOpen) {
            monitorCloseTimer.stop();
            monitorLayoutOpen = true;
        } else if (monitorLayoutOpen) {
            monitorCloseTimer.restart();
        }
    }
    onWallpaperOpenChanged: {
        if (wallpaperOpen) {
            wallpaperCloseTimer.stop();
            wallpaperLayoutOpen = true;
        } else if (wallpaperLayoutOpen) {
            wallpaperCloseTimer.restart();
        }
    }
    onBluetoothOpenChanged: {
        if (bluetoothOpen) {
            bluetoothCloseTimer.stop();
            bluetoothLayoutOpen = true;
        } else if (bluetoothLayoutOpen) {
            bluetoothCloseTimer.restart();
        }
    }
    onNightLightOpenChanged: {
        if (nightLightOpen) {
            nightLightCloseTimer.stop();
            nightLightLayoutOpen = true;
        } else if (nightLightLayoutOpen) {
            nightLightCloseTimer.restart();
        }
    }
    onNetworkOpenChanged: {
        if (networkOpen) {
            networkCloseTimer.stop();
            networkLayoutOpen = true;
            NetworkService.refresh();
        } else if (networkLayoutOpen) {
            networkCloseTimer.restart();
        }
    }

    Timer { id: deviceCloseTimer; interval: deviceMotion.closeDuration + 20; onTriggered: root.deviceLayoutOpen = false }
    Timer { id: monitorCloseTimer; interval: monitorMotion.closeDuration + 20; onTriggered: root.monitorLayoutOpen = false }
    Timer { id: wallpaperCloseTimer; interval: wallpaperMotion.closeDuration + 20; onTriggered: root.wallpaperLayoutOpen = false }
    Timer { id: bluetoothCloseTimer; interval: bluetoothMotion.closeDuration + 20; onTriggered: root.bluetoothLayoutOpen = false }
    Timer { id: nightLightCloseTimer; interval: nightLightMotion.closeDuration + 20; onTriggered: root.nightLightLayoutOpen = false }
    Timer { id: networkCloseTimer; interval: networkMotion.closeDuration + 20; onTriggered: root.networkLayoutOpen = false }
    width: 82
    height: 30
    radius: Theme.radius
    color: groupMouse.containsMouse
        ? Qt.rgba(Theme.popupSurface0.r, Theme.popupSurface0.g,
                  Theme.popupSurface0.b, 0.72)
        : "transparent"
    Behavior on color { ColorAnimation { duration: 140 } }

    // Discover once at startup so the initial brightness slider can select the
    // first display without requiring the display picker to be opened first.
    Component.onCompleted: root.refreshMonitors()
    function refresh() {
        // Refresh the selected display when the popup is opened.
        if (root.selectedDisplay >= 0 && !brightnessQuery.running)
            brightnessQuery.running = true;
    }

    function setVolume(value) {
        OsdService.suppressVolume();
        AudioService.setVolume(value);
    }

    function setDefaultOutput(node) { AudioService.setDefaultOutput(node); }

    function refreshMonitors() {
        if (!monitorsQuery.running) monitorsQuery.running = true;
        // Re-read the level for whichever panel is now selected.
        if (root.selectedDisplay >= 0 && !brightnessQuery.running)
            brightnessQuery.running = true;
        if (!friendlyQuery.running) friendlyQuery.running = true;
    }

    Row {
        anchors.centerIn: parent
        spacing: 7

        StatusIcon {
            id: volumeIcon
            icon: AudioService.muted || AudioService.volume <= 0
                ? "volume_off" : AudioService.volume < 0.5 ? "volume_down" : "volume_up"
        }
        StatusIcon {
            icon: !BluetoothService.powered ? "bluetooth_disabled"
                : BluetoothService.connected ? "bluetooth_connected" : "bluetooth"
        }
        StatusIcon { icon: root.networkIcon() }
    }

    MouseArea {
        id: groupMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.togglePopup()
        onWheel: wheel => {
            // The MouseArea covers the whole three-icon control. Convert the
            // event position into the speaker icon's coordinates so only
            // scrolling directly over that icon changes the volume.
            const point = volumeIcon.mapFromItem(groupMouse, wheel.x, wheel.y);
            const overVolume = point.x >= 0 && point.x < volumeIcon.width
                && point.y >= 0 && point.y < volumeIcon.height;
            if (!overVolume) {
                wheel.accepted = false;
                return;
            }

            const delta = wheel.angleDelta.y !== 0
                ? wheel.angleDelta.y : wheel.pixelDelta.y;
            if (delta !== 0) {
                root.setVolume(AudioService.volume + (delta > 0 ? 0.05 : -0.05));
                wheel.accepted = true;
            }
        }
    }

    function networkIcon(): string {
        if (NetworkService.ethernetConnected) return "lan";
        if (!NetworkService.wifiConnected) return "signal_wifi_off";
        if (NetworkService.wifiStrength < 34) return "network_wifi_1_bar";
        if (NetworkService.wifiStrength < 67) return "network_wifi_2_bar";
        return "signal_wifi_4_bar";
    }

    component StatusIcon: Text {
        required property string icon
        width: 18
        height: 26
        text: icon
        color: Theme.colors.text
        font.family: Theme.iconFamily
        font.pixelSize: 18
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Process {
        id: brightnessQuery
        command: ["ddcutil", "getvcp", "10", "--terse", "--noverify",
                  "--display", String(root.selectedDisplay)]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/VCP\s+10\s+C\s+(\d+)\s+(\d+)/i);
                if (match && !brightnessSlider.dragging) {
                    const current = Math.round(Number(match[1]) * 100 / Number(match[2]));
                    root.brightness = current >= 0 && current <= 100 ? current : -1;
                }
            }
        }
        // A non-zero exit means the display does not speak DDC/CI (or ddcutil
        // is not installed). Report "unknown" rather than a stale percentage.
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.brightness = -1;
        }
    }

    Process {
        id: monitorsQuery
        command: ["ddcutil", "detect", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                let current = null;
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; ++i) {
                    const displayMatch = lines[i].match(/^\s*Display\s+(\d+)/);
                    if (displayMatch) {
                        current = {
                            id: Number(displayMatch[1]),
                            description: "Display " + displayMatch[1],
                            connector: "",
                            model: ""
                        };
                        found.push(current);
                        continue;
                    }
                    if (!current) continue;
                    // Keep the connector and the model name apart: the connector
                    // is shown as a dim subtitle, the model as the label, and
                    // the friendly EDID name wins over both when it is read.
                    const connectorMatch = lines[i].match(/^\s*DRM connector:\s*(.+)$/);
                    if (connectorMatch) {
                        current.connector = connectorMatch[1].trim();
                        continue;
                    }
                    const modelMatch = lines[i].match(/^\s*(?:Monitor|Model):\s*(.+)$/);
                    if (modelMatch) {
                        current.model = modelMatch[1].trim();
                        if (current.model.length > 0)
                            current.description = current.model;
                    }
                }
                root.monitors = found;
                if (found.length > 0
                        && !found.some(monitor => monitor.id === root.selectedDisplay))
                    root.selectedDisplay = found[0].id;
                if (found.length === 0)
                    root.brightness = -1;
                else if (!brightnessQuery.running)
                    brightnessQuery.running = true;
                // ddcutil names the port, not the panel. The
                // friendly name comes from the monitor's EDID, so read it and
                // prefer it, keeping the connector only as a fallback.
                friendlyQuery.running = true;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.monitors = [];
                root.brightness = -1;
            }
        }
    }

    // Prints "connector<TAB>name" per display, reading the EDID monitor name.
    Process {
        id: friendlyQuery
        command: ["python3", Quickshell.shellPath("scripts/monitor-names.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const byConnector = {};
                for (let i = 0; i < lines.length; ++i) {
                    const parts = lines[i].split("\t");
                    if (parts.length >= 2 && parts[0].length && parts[1].length)
                        byConnector[parts[0]] = parts[1].trim();
                }
                if (Object.keys(byConnector).length === 0)
                    return;
                // Reassigning the array (rather than mutating in place) is what
                // makes the ListView pick the new names up.
                const updated = root.monitors.map(monitor => {
                    // Prefer an exact connector match; fall back to the card
                    // index, since ddcutil display ids are 1-based card indices.
                    let name = byConnector[monitor.connector] || "";
                    if (!name) {
                        const key = "card" + monitor.id + "-";
                        for (const connector in byConnector) {
                            if (connector.indexOf(key) === 0) {
                                name = byConnector[connector];
                                break;
                            }
                        }
                    }
                    if (!name || name === monitor.description)
                        return monitor;
                    return Object.assign({}, monitor, { description: name });
                });
                root.monitors = updated;
            }
        }
    }

    // Invisible full-screen layer to catch clicks outside the popup
    // This layer is behind the popup to allow clicking outside to dismiss
    PanelWindow {
        id: dismissLayer
        screen: popup.screen
        visible: root.popupOpen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:controlcenter-dismiss"
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        MouseArea {
            anchors.fill: parent
            onPressed: mouse => {
                root.popupOpen = false;
                mouse.accepted = true;
            }
        }
    }

    PanelWindow {
        id: popup
        readonly property int cornerRadius: 20
        visible: popupMotion.active
        screen: root.QsWindow.window?.screen ?? null
        anchors { top: true; right: true }
        margins.top: OverlayService.topMargin(screen)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        // Reuse the bar-glass blur and stationary attached-popup rules.
        WlrLayershell.namespace: "quickshell:popup-backdrop"
        focusable: root.popupOpen
        implicitWidth: 420 + cornerRadius
        readonly property real panelHeight: root.toggleMenuVisible
            ? 106 + (root.networkLayoutOpen ? root.networkPanelHeight
                : root.bluetoothLayoutOpen ? root.bluetoothPanelHeight
                : root.wallpaperLayoutOpen ? root.wallpaperPanelHeight : root.nightLightPanelHeight)
            : 548 + (root.sliderMenuHeight > 0 ? root.sliderMenuHeight - 96 : 0)
        readonly property real availableHeight: (screen ? screen.height : 1080) - Theme.barHeight - 48
        // Reserve the surface once. Per-frame native window resizes wait on
        // the compositor; only the scene-graph panel should animate.
        implicitHeight: Math.max(panelHeight, availableHeight) + cornerRadius
        property real visualHeight: panelHeight + (trayMenuHost.visible ? trayMenuHost.implicitHeight + 6 : 0)
        Behavior on visualHeight {
            enabled: root.popupOpen
            NumberAnimation {
                id: panelResize
                duration: 155
                easing.type: Easing.OutCubic
            }
        }
        mask: Region { item: panelSurface }
        color: "transparent"

        AttachedPanel {
            id: panelSurface
            focus: root.popupOpen
            Keys.onEscapePressed: event => {
                if (root.sessionConfirmationOpen) root.cancelSessionAction();
                else if (root.toggleMenuOpen) root.closeToggleMenus();
                else if (root.devicesOpen || root.monitorsOpen) {
                    root.devicesOpen = false;
                    root.monitorsOpen = false;
                } else root.popupOpen = false;
                event.accepted = true;
            }
            flowProgress: popupMotion.progress
            flowStrength: 0.12
            flowAnchor: Qt.vector2d(1, 0)
            // Position bindings also keep the window's click region in step.
            x: popupMotion.offsetX
            y: popupMotion.offsetY
            width: parent.width
            height: popup.visualHeight + popup.cornerRadius
            cornerRadius: popup.cornerRadius
            // A slightly stronger tint keeps the blurred window unobtrusive.
            color: Qt.rgba(Theme.colors.base.r, Theme.colors.base.g,
                           Theme.colors.base.b, 0.68)
            enabled: root.popupOpen
            transform: Scale {
                origin.x: panelSurface.width
                origin.y: 0
                xScale: popupMotion.scaleX
                yScale: popupMotion.scaleY
            }

            Item {
                id: controlViewport
                anchors.fill: parent
                anchors.margins: 16
                anchors.leftMargin: 16 + popup.cornerRadius
                anchors.bottomMargin: 16 + popup.cornerRadius
                clip: true

            ColumnLayout {
                id: controlContent
                width: controlViewport.width
                // Tray menus must not participate in this layout: adding a
                // row redistributes space and shifts the existing controls.
                height: popup.panelHeight - 32
                spacing: 10

                Rectangle {
                    id: userSummary
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    Layout.minimumHeight: 64
                    Layout.maximumHeight: 64
                    radius: 22
                    color: Theme.popupSurface0

                    readonly property bool userHovered: userSummaryHover.hovered
                        && !root.toggleMenuVisible && root.pendingSessionCommand === null
                    property real hoverProgress: userHovered ? 1 : 0
                    Behavior on hoverProgress {
                        NumberAnimation { duration: 240; easing.type: Easing.InOutCubic }
                    }

                    // Observe the entire card, including the session buttons.
                    HoverHandler {
                        id: userSummaryHover
                        blocking: false
                    }

                    RowLayout {
                        id: userHeaderContent
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: root.toggleMenuVisible ? 48
                            : 10 + headerSessionButtons.width + 8
                              + headerUptime.implicitWidth + headerSeparator.implicitWidth + 15
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        spacing: 11

                        ClippingRectangle {
                            width: 42
                            height: 42
                            radius: Theme.radius
                            color: Theme.popupSurface1
                            contentUnderBorder: true

                            Image {
                                id: userImage
                                anchors.fill: parent
                                source: "file://" + Quickshell.env("HOME") + "/.face"
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready && !root.toggleMenuVisible
                            }
                            Text {
                                font.family: root.toggleMenuVisible ? Theme.iconFamily : Theme.textFamily
                                anchors.centerIn: parent
                                text: root.toggleMenuVisible
                                    ? root.networkLayoutOpen ? "lan" : root.bluetoothLayoutOpen ? "bluetooth"
                                      : root.wallpaperLayoutOpen ? "wallpaper" : "bedtime"
                                    : SystemService.fullName.charAt(0).toUpperCase()
                                visible: root.toggleMenuVisible || userImage.status !== Image.Ready
                                color: Theme.colors.mauve
                                font.pixelSize: 18
                                font.bold: true
                            }
                        }

                        ColumnLayout {
                            id: userIdentity
                            // Reserve room for the uptime and all four buttons
                            // so longer names elide without overlapping them.
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                id: userName
                                Layout.fillWidth: true
                                text: root.toggleMenuVisible
                                    ? root.networkLayoutOpen ? "Internet" : root.bluetoothLayoutOpen ? "Bluetooth"
                                      : root.wallpaperLayoutOpen ? "Wallpapers" : "Night light"
                                    : SystemService.fullName
                                color: Theme.colors.text
                                font.family: Theme.textFamily
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }

                    }

                    Text {
                        id: headerSeparator
                        z: 1
                        visible: !root.toggleMenuVisible
                        readonly property real nameEndX:
                            userHeaderContent.x + userIdentity.x + userName.x
                            + Math.min(userName.implicitWidth, userName.width)
                        readonly property real hoverX: nameEndX + 7
                        x: nameEndX + 7 * userSummary.hoverProgress
                        anchors.verticalCenter: parent.verticalCenter
                        text: "-"
                        color: Theme.colors.textDim
                        font.family: Theme.textFamily
                        font.pixelSize: 12
                        opacity: userSummary.hoverProgress
                    }

                    Text {
                        id: headerUptime
                        z: 1
                        visible: !root.toggleMenuVisible
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property real hoveredX:
                            headerSeparator.hoverX + headerSeparator.width + 8
                        readonly property real restingX: parent.width - width - 10
                        x: restingX + (hoveredX - restingX) * userSummary.hoverProgress
                        text: SystemService.uptime
                        color: Theme.colors.textDim
                        font.family: Theme.textFamily
                        font.pixelSize: 10
                    }

                    Row {
                        id: headerSessionButtons
                        z: 1
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        // Reveal after the uptime clears this space, and
                        // hide first when the pointer leaves the card.
                        visible: !root.toggleMenuVisible && sessionButtonsMotion.active
                        enabled: userSummary.userHovered && userSummary.hoverProgress >= 0.99
                        transform: [
                            Translate { y: sessionButtonsMotion.offsetY },
                            Scale {
                                origin.x: headerSessionButtons.width
                                origin.y: headerSessionButtons.height / 2
                                xScale: sessionButtonsMotion.scaleX
                                yScale: sessionButtonsMotion.scaleY
                            }
                        ]
                        PopupMotion {
                            id: sessionButtonsMotion
                            opened: userSummary.userHovered && userSummary.hoverProgress >= 0.99
                            attached: false
                            distance: 10
                            openDuration: 190
                            closeDuration: 110
                        }

                        Repeater {
                            model: [
                                { icon: "lock", label: "Lock screen", command: ["loginctl", "lock-session"], danger: false },
                                { icon: "logout", label: "Log out", command: ["hyprctl", "dispatch", "exit"], danger: false },
                                { icon: "restart_alt", label: "Restart", command: ["systemctl", "reboot"], danger: true },
                                { icon: "power_settings_new", label: "Power off", command: ["systemctl", "poweroff"], danger: true }
                            ]
                            delegate: Item {
                                required property var modelData
                                width: 22
                                height: 30
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    color: headerSessionMouse.containsMouse && modelData.danger
                                           ? Theme.colors.red : Theme.colors.text
                                    font.family: Theme.iconFamily
                                    font.pixelSize: 17
                                }
                                MouseArea {
                                    id: headerSessionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.requestSessionAction(modelData.command,
                                                                          modelData.label,
                                                                          modelData.icon)
                                }
                            }
                        }
                    }

                    ControlButton {
                        z: 2
                        visible: root.toggleMenuVisible
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        icon: "arrow_back"
                        Accessible.name: "Back to control center"
                        onClicked: root.closeToggleMenus()
                    }

                    Rectangle {
                        id: sessionConfirmation
                        anchors.fill: parent
                        z: 2
                        visible: sessionConfirmationMotion.active
                        enabled: root.sessionConfirmationOpen
                        radius: parent.radius
                        color: Theme.popupSurface1
                        transform: [
                            Translate { y: sessionConfirmationMotion.offsetY },
                            Scale {
                                origin.x: sessionConfirmation.width / 2
                                origin.y: 0
                                xScale: sessionConfirmationMotion.scaleX
                                yScale: sessionConfirmationMotion.scaleY
                            }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 9
                            spacing: 8
                            Text {
                                text: root.pendingSessionIcon
                                color: Theme.colors.red
                                font.family: Theme.iconFamily
                                font.pixelSize: 18
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.pendingSessionLabel + "?"
                                color: Theme.colors.text
                                font.family: Theme.textFamily
                                font.pixelSize: 12
                                font.bold: true
                            }
                            ControlButton {
                                icon: "close"
                                Accessible.name: "Cancel session action"
                                onClicked: root.cancelSessionAction()
                            }
                            ControlButton {
                                icon: "check"
                                danger: true
                                Accessible.name: "Confirm session action"
                                onClicked: root.confirmSessionAction()
                            }
                        }
                    }
                }

                GridLayout {
                    visible: !root.toggleMenuVisible
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.quickToggleHeight
                    columns: 2
                    rowSpacing: 8
                    columnSpacing: 8
                    ControlTile {
                        label: "Internet"
                        subtitle: NetworkService.connectedCount > 1 ? NetworkService.connectedCount + " connections active"
                            : NetworkService.ethernetConnected ? NetworkService.ethernetDevice
                            : NetworkService.wifiConnected ? NetworkService.connectedSsid : "Manage connections"
                        icon: root.networkIcon()
                        checked: NetworkService.connectedCount > 0
                        expandable: true
                        showSwitch: false
                        onExpansionRequested: root.openMenu("network")
                    }
                    ControlTile {
                        label: "Bluetooth"
                        subtitle: !BluetoothService.available ? "No adapter"
                            : BluetoothService.connected ? BluetoothService.connectedDevices.length + " connected"
                            : BluetoothService.powered ? "Ready to connect" : "Off"
                        icon: "bluetooth"
                        checked: BluetoothService.powered
                        toggleAvailable: BluetoothService.available
                        expandable: true
                        onToggled: value => BluetoothService.setPowered(value)
                        onExpansionRequested: root.openMenu("bluetooth")
                    }
                    ControlTile {
                        label: "Dark mode"
                        subtitle: Theme.darkMode ? "Dark appearance" : "Light appearance"
                        icon: Theme.darkMode ? "dark_mode" : "light_mode"
                        checked: Theme.darkMode
                        onToggled: value => {
                            Theme.darkMode = value;
                            Quickshell.execDetached(["sh", Quickshell.shellPath("scripts/theme-toggle.sh"), value ? "dark" : "light"]);
                        }
                    }
                    ControlTile {
                        label: "Choose wallpaper"
                        subtitle: WallpaperManager.enabled ? "Explore your collection" : "Wallpaper paused"
                        icon: "wallpaper"
                        thumbnail: WallpaperLibrary.currentThumbnail
                        checked: WallpaperManager.enabled
                        expandable: true
                        onToggled: value => WallpaperManager.setEnabled(value)
                        onExpansionRequested: root.openMenu("wallpaper")
                    }
                    ControlTile {
                        label: "Do not disturb"
                        subtitle: Config.doNotDisturb ? "Notifications silenced" : "Notifications allowed"
                        icon: Config.doNotDisturb ? "notifications_off" : "notifications"
                        checked: Config.doNotDisturb
                        onToggled: value => Config.setDoNotDisturb(value)
                    }
                    ControlTile {
                        label: "Night light"
                        subtitle: NightLightService.active ? Config.nightLightTemperature + " K"
                            : NightLightService.retrying ? "Waiting for displays" : Config.nightLightEnabled ? "Starting…" : "Off"
                        icon: "bedtime"
                        checked: Config.nightLightEnabled
                        toggleAvailable: NightLightService.available
                        expandable: true
                        onToggled: value => NightLightService.setEnabled(value)
                        onExpansionRequested: root.openMenu("nightLight")
                    }
                }

                Item {
                    id: expandedMenu
                    readonly property var motion: root.networkLayoutOpen ? networkMotion
                        : root.bluetoothLayoutOpen ? bluetoothMotion
                        : root.wallpaperLayoutOpen ? wallpaperMotion : nightLightMotion
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? (root.networkLayoutOpen ? root.networkPanelHeight
                        : root.bluetoothLayoutOpen ? root.bluetoothPanelHeight
                        : root.wallpaperLayoutOpen ? root.wallpaperPanelHeight : root.nightLightPanelHeight) : 0
                    Layout.minimumHeight: Layout.preferredHeight
                    Layout.maximumHeight: Layout.preferredHeight
                    visible: root.toggleMenuVisible && motion.active
                    enabled: root.toggleMenuOpen
                    clip: true
                    transform: [
                        Translate { y: expandedMenu.motion.offsetY },
                        Scale {
                            origin.x: root.wallpaperLayoutOpen ? expandedMenu.width * 0.75 : expandedMenu.width / 2
                            origin.y: root.wallpaperLayoutOpen ? expandedMenu.height * 0.35 : 0
                            xScale: expandedMenu.motion.scaleX
                            yScale: expandedMenu.motion.scaleY
                        }
                    ]
                    NetworkMenu { anchors.fill: parent; visible: root.networkLayoutOpen; active: root.popupOpen && root.networkOpen }
                    BluetoothMenu { anchors.fill: parent; visible: root.bluetoothLayoutOpen; active: root.popupOpen && root.bluetoothOpen }
                    WallpaperMenu { anchors.fill: parent; visible: root.wallpaperLayoutOpen; active: root.popupOpen && root.wallpaperOpen }
                    NightLightMenu { anchors.fill: parent; visible: root.nightLightLayoutOpen; active: root.popupOpen && root.nightLightOpen }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.toggleMenuVisible && !(root.deviceLayoutOpen || root.monitorLayoutOpen)
                    Layout.preferredHeight: visible ? 96 : 0
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 96
                        radius: 22
                        color: Theme.popupSurface0
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Volume"; font.family: Theme.textFamily; font.pixelSize: 12; font.weight: Font.DemiBold; color: Theme.colors.text }
                                Item { Layout.fillWidth: true }
                                ControlButton {
                                    implicitHeight: 26
                                    implicitWidth: 28
                                    icon: AudioService.muted ? "volume_off" : "volume_up"
                                    label: ""
                                    enabled: !!AudioService.output
                                    onClicked: if (AudioService.output && AudioService.output.audio) AudioService.output.audio.muted = !AudioService.muted
                                }
                                ControlButton {
                                    implicitHeight: 26
                                    implicitWidth: 28
                                    icon: "tune"
                                    onClicked: { root.devicesOpen = true; root.monitorsOpen = false; }
                                }
                            }
                            ControlSlider {
                                id: volumeSlider
                                Layout.fillWidth: true
                                minimum: 0
                                maximum: 1
                                step: 0.01
                                value: root.volume
                                valueText: AudioService.muted ? "Muted" : Math.round(root.volume * 100) + "%"
                                icon: AudioService.muted ? "volume_off" : "volume_up"
                                label: "Volume"
                                accent: Theme.colors.mauve
                                enabled: !!AudioService.output
                                onMoved: value => { root.volume = value; root.setVolume(value); }
                                onCommitted: value => root.setVolume(value)
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 96
                        radius: 22
                        color: Theme.popupSurface0
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Brightness"; font.family: Theme.textFamily; font.pixelSize: 12; font.weight: Font.DemiBold; color: Theme.colors.text }
                                Item { Layout.fillWidth: true }
                                ControlButton {
                                    implicitHeight: 26
                                    implicitWidth: 28
                                    icon: "desktop_windows"
                                    onClicked: { root.monitorsOpen = true; root.devicesOpen = false; root.refreshMonitors(); }
                                }
                            }
                            ControlSlider {
                                id: brightnessSlider
                                Layout.fillWidth: true
                                minimum: 0
                                maximum: 100
                                step: 1
                                value: Math.max(0, root.brightness)
                                enabled: root.brightness >= 0
                                opacity: enabled ? 1 : 0.45
                                icon: "brightness_6"
                                label: "Brightness"
                                valueText: root.brightness < 0 ? "N/A" : root.brightness + "%"
                                accent: Theme.colors.mauve
                                onMoved: value => { OsdService.suppressBrightness(); root.brightness = Math.round(value); }
                                onCommitted: value => Quickshell.execDetached(["ddcutil", "setvcp", "10", String(Math.round(value)), "--display", String(root.selectedDisplay)])
                            }
                        }
                    }
                }

                Rectangle {
                    id: sliderMenu
                    readonly property var motion: root.deviceLayoutOpen ? deviceMotion : monitorMotion
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.sliderMenuHeight
                    Layout.minimumHeight: Layout.preferredHeight
                    Layout.maximumHeight: Layout.preferredHeight
                    radius: 22
                    color: Theme.popupSurface0
                    visible: !root.toggleMenuVisible && (root.deviceLayoutOpen || root.monitorLayoutOpen) && motion.active
                    enabled: root.devicesOpen || root.monitorsOpen
                    clip: true
                    transform: [
                        Translate { y: sliderMenu.motion.offsetY },
                        Scale {
                            origin.x: sliderMenu.width / 2
                            origin.y: 0
                            xScale: sliderMenu.motion.scaleX
                            yScale: sliderMenu.motion.scaleY
                        }
                    ]

                    Rectangle {
                        z: 1
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 6
                        anchors.rightMargin: 6
                        width: 28
                        height: 28
                        radius: Theme.radius
                        color: sliderMenuBackMouse.containsMouse ? Theme.popupSurface2 : Theme.popupSurface1
                        Text {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            color: Theme.colors.text
                            font.family: Theme.iconFamily
                            font.pixelSize: 17
                        }
                        MouseArea {
                            id: sliderMenuBackMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.devicesOpen = false;
                                root.monitorsOpen = false;
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        ControlDevicePicker {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.deviceLayoutOpen
                            title: "Audio output"
                            emptyText: "No audio output devices"
                            selectedId: root.defaultOutput
                            entries: root.outputs.map(node => ({
                                id: node.id, label: AudioService.label(node), data: node,
                                subtitle: node.id === root.defaultOutput ? "Current output" : "Switch to this output",
                                icon: /bluez|bluetooth/i.test(node.name || "") ? "headphones" : "speaker"
                            }))
                            onSelected: entry => root.setDefaultOutput(entry.data)
                        }
                        ControlDevicePicker {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.monitorLayoutOpen
                            title: "Display brightness"
                            emptyText: "No DDC/CI displays found"
                            selectedId: root.selectedDisplay
                            entries: root.monitors.map(monitor => ({
                                id: monitor.id, label: monitor.description, icon: "desktop_windows",
                                subtitle: (monitor.connector || "Display " + monitor.id).replace(/^card\d+-/, "")
                            }))
                            onSelected: entry => {
                                root.selectedDisplay = entry.id;
                                if (!brightnessQuery.running) brightnessQuery.running = true;
                            }
                        }
                    }
                }

                RowLayout {
                    id: trayDateRow
                    visible: !root.toggleMenuVisible
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 8
                        text: root.trayDate
                        color: Theme.colors.textDim
                        font.family: Theme.textFamily
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Tray {
                        id: controlTray
                        Layout.alignment: Qt.AlignRight | Qt.AlignTop
                        menuHost: trayMenuHost
                        onAppActivated: root.popupOpen = false
                    }
                }

            }

                Item {
                    id: trayMenuHost
                    anchors.top: controlContent.bottom
                    anchors.topMargin: 6
                    width: controlViewport.width
                    height: implicitHeight
                    // Keep the slot until exit completes; switching tray apps
                    // still uses the existing horizontal page transition.
                    visible: controlTray.activeMenu !== null
                    enabled: controlTray.menuOpen && root.popupOpen
                    implicitHeight: controlTray.activeMenu ? controlTray.activeMenu.height : 0
                    transform: [
                        Translate { y: trayMenuMotion.offsetY },
                        Scale {
                            origin.x: trayMenuHost.width / 2
                            origin.y: 0
                            xScale: trayMenuMotion.scaleX
                            yScale: trayMenuMotion.scaleY
                        }
                    ]
                    PopupMotion {
                        id: trayMenuMotion
                        opened: controlTray.menuOpen && root.popupOpen
                        attached: false
                        distance: 18
                        onClosed: controlTray.finishMenuClose()
                    }
                    // Grow below the existing controls; long menus scroll
                    // internally within the remaining screen space.
                    readonly property real maximumMenuHeight: Math.max(0,
                        popup.availableHeight - popup.panelHeight - 6)
                }

            }

            // Observe from the shared parent: a sibling overlay here steals
            // hover from the user card even with blocking disabled.
            HoverHandler {
                blocking: false
                function dismissTrayMenuAboveControls() {
                    if (hovered && point.position.y < controlViewport.y + trayDateRow.y)
                        controlTray.closeMenus();
                }
                onHoveredChanged: dismissTrayMenuAboveControls()
                onPointChanged: dismissTrayMenuAboveControls()
            }
        }
    }

}
