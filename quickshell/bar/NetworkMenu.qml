import QtQuick
import QtQuick.Layouts
import "../components"
import "../widgets"
import "../modules/network.js" as Network

Item {
    id: root
    property bool active: true
    property string expandedDevice: ""
    property var pendingNetwork: null
    property bool showPassword: false
    implicitHeight: 420

    function chooseNetwork(network) {
        if (network.active) {
            NetworkService.disconnectWifi(network.device);
        } else if (network.security.length) {
            pendingNetwork = network;
            showPassword = false;
            password.text = "";
            scroll.contentY = 0;
            Qt.callLater(function() { password.forceActiveFocus(); });
        } else {
            NetworkService.connectWifi(network, "");
        }
    }
    function connectPending() {
        if (!pendingNetwork) return;
        NetworkService.connectWifi(pendingNetwork, password.text);
        password.text = "";
        pendingNetwork = null;
    }
    onActiveChanged: {
        if (active) NetworkService.refresh();
        else { pendingNetwork = null; password.text = ""; }
    }
    Component.onCompleted: if (active) NetworkService.refresh()

    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            ControlSectionHeader {
                Layout.fillWidth: true
                title: "Your connections"
                subtitle: !NetworkService.available ? "NetworkManager is unavailable"
                    : NetworkService.connectedCount + (NetworkService.connectedCount === 1 ? " active connection" : " active connections")
                        + " · " + NetworkService.interfaces.length + (NetworkService.interfaces.length === 1 ? " interface" : " interfaces")
                icon: "router"
            }
            ControlButton {
                icon: "refresh"
                label: ""
                busy: NetworkService.refreshing
                Accessible.name: "Refresh network connections"
                onClicked: NetworkService.refresh()
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: errorText.implicitHeight + 22
            visible: NetworkService.lastError.length > 0
            color: Theme.popupSurface1
            radius: 16
            RowLayout {
                anchors.fill: parent
                anchors.margins: 11
                spacing: 9
                Text { text: "error_outline"; font.family: Theme.iconFamily; font.pixelSize: 19; color: Theme.colors.red }
                Text {
                    id: errorText
                    Layout.fillWidth: true
                    text: NetworkService.lastError
                    font.family: Theme.textFamily
                    font.pixelSize: 10
                    color: Theme.colors.red
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                ControlButton { icon: "close"; implicitHeight: 28; implicitWidth: 28; Accessible.name: "Dismiss network error"; onClicked: NetworkService.clearError() }
            }
        }
        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            ColumnLayout {
                id: content
                width: scroll.width
                spacing: 10
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 66
                    visible: NetworkService.hasWifi
                    color: Theme.popupSurface0
                    radius: 22
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12
                        Text {
                            text: NetworkService.radioBusy ? "sync" : "wifi"
                            font.family: Theme.iconFamily
                            font.pixelSize: 25
                            color: NetworkService.wifiEnabled ? Theme.colors.mauve : Theme.colors.textDim
                            RotationAnimator on rotation { running: NetworkService.radioBusy && root.active; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: "Wi-Fi"; color: Theme.colors.text; font.family: Theme.textFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text {
                                text: NetworkService.radioBusy ? "Updating radio…" : NetworkService.wifiEnabled ? "Discover nearby networks" : "Radio is off"
                                color: Theme.colors.textDim
                                font.family: Theme.textFamily
                                font.pixelSize: 10
                            }
                        }
                        ControlSwitch {
                            checked: NetworkService.wifiEnabled
                            enabled: NetworkService.available && !NetworkService.radioBusy
                            label: "Wi-Fi radio"
                            onToggled: value => NetworkService.setWifiEnabled(value)
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: passwordContent.implicitHeight + 28
                    visible: root.pendingNetwork !== null
                    color: Theme.popupSurface1
                    radius: 22
                    border.width: 1
                    border.color: Theme.colors.mauve
                    ColumnLayout {
                        id: passwordContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 10
                        Text {
                            Layout.fillWidth: true
                            text: root.pendingNetwork ? root.pendingNetwork.ssid : ""
                            color: Theme.colors.text
                            font.family: Theme.textFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.pendingNetwork && root.pendingNetwork.security.indexOf("802.1X") >= 0
                                ? "Enterprise Wi-Fi needs a saved connection profile."
                                : "Enter a password, or use a connection you have saved."
                            color: Theme.colors.textDim
                            font.family: Theme.textFamily
                            font.pixelSize: 10
                            wrapMode: Text.Wrap
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 42
                            visible: !root.pendingNetwork || root.pendingNetwork.security.indexOf("802.1X") < 0
                            color: Theme.popupSurface0
                            radius: 14
                            border.width: password.activeFocus ? 1 : 0
                            border.color: Theme.colors.mauve
                            TextInput {
                                id: password
                                anchors.left: parent.left
                                anchors.right: revealPassword.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                anchors.rightMargin: 6
                                color: Theme.colors.text
                                font.family: Theme.textFamily
                                font.pixelSize: 12
                                echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                selectByMouse: true
                                clip: true
                                onAccepted: root.connectPending()
                                Accessible.name: "Wi-Fi password"
                                Text {
                                    visible: !password.text.length && !password.activeFocus
                                    text: "Password"
                                    color: Theme.colors.textDim
                                    font: password.font
                                }
                            }
                            ControlButton {
                                id: revealPassword
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                icon: root.showPassword ? "visibility_off" : "visibility"
                                implicitWidth: 32
                                implicitHeight: 32
                                Accessible.name: root.showPassword ? "Hide password" : "Show password"
                                onClicked: root.showPassword = !root.showPassword
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            ControlButton { label: "Cancel"; onClicked: { root.pendingNetwork = null; password.text = ""; } }
                            ControlButton {
                                label: password.text.length ? "Connect" : "Use saved"
                                icon: "wifi"
                                accent: true
                                onClicked: root.connectPending()
                            }
                        }
                    }
                }
                Repeater {
                    model: NetworkService.interfaces
                    delegate: Rectangle {
                        id: deviceCard
                        required property var modelData
                        readonly property bool busy: !!NetworkService.busyDevices[modelData.device]
                        readonly property bool expanded: root.expandedDevice === modelData.device
                        Layout.fillWidth: true
                        implicitHeight: deviceContent.implicitHeight + 28
                        radius: 22
                        color: Theme.popupSurface0
                        border.width: modelData.connected ? 1 : 0
                        border.color: Qt.rgba(Theme.colors.mauve.r, Theme.colors.mauve.g, Theme.colors.mauve.b, 0.30)
                        ColumnLayout {
                            id: deviceContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 10
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle {
                                    implicitWidth: 38
                                    implicitHeight: 38
                                    radius: 15
                                    color: deviceCard.modelData.connected ? Theme.colors.mauve : Theme.popupSurface2
                                    Text {
                                        anchors.centerIn: parent
                                        text: deviceCard.busy ? "sync" : deviceCard.modelData.type === "ethernet" ? "settings_ethernet" : deviceCard.modelData.type === "wifi" ? "wifi" : "lan"
                                        font.family: Theme.iconFamily
                                        font.pixelSize: 22
                                        color: deviceCard.modelData.connected ? Theme.colors.crust : Theme.colors.textDim
                                        RotationAnimator on rotation { running: deviceCard.busy && root.active; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        Layout.fillWidth: true
                                        text: deviceCard.modelData.device
                                        font.family: Theme.textFamily
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: Theme.colors.text
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: deviceCard.busy ? "Updating connection…" : Network.deviceLabel(deviceCard.modelData.type) + " · " + Network.stateLabel(deviceCard.modelData, NetworkService.wifiEnabled)
                                        color: deviceCard.modelData.connected ? Theme.colors.mauve : Theme.colors.textDim
                                        font.family: Theme.textFamily
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }
                                ControlSwitch {
                                    checked: deviceCard.modelData.connected
                                    enabled: NetworkService.available && deviceCard.modelData.canControl && !deviceCard.busy
                                        && (deviceCard.modelData.type !== "wifi" || NetworkService.wifiEnabled)
                                    label: "Connect " + deviceCard.modelData.device
                                    onToggled: value => NetworkService.setDeviceConnected(deviceCard.modelData.device, value)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: deviceCard.modelData.connected
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        Layout.fillWidth: true
                                        text: deviceCard.modelData.connection || "Active connection"
                                        color: Theme.colors.text
                                        font.family: Theme.textFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: deviceCard.modelData.addresses.length > 0
                                        text: deviceCard.modelData.addresses.join(" · ")
                                        color: Theme.colors.textDim
                                        font.family: Theme.textFamily
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }
                                ControlButton {
                                    icon: deviceCard.expanded ? "expand_less" : "info_outline"
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    Accessible.name: "Connection details for " + deviceCard.modelData.device
                                    onClicked: root.expandedDevice = deviceCard.expanded ? "" : deviceCard.modelData.device
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: deviceCard.expanded
                                text: [deviceCard.modelData.gateway ? "Gateway  " + deviceCard.modelData.gateway : "",
                                    deviceCard.modelData.ipv6.length ? "IPv6  " + deviceCard.modelData.ipv6.join("\n          ") : "",
                                    deviceCard.modelData.mac ? "MAC  " + deviceCard.modelData.mac : ""].filter(value => value.length).join("\n")
                                font.family: Theme.textFamily
                                font.pixelSize: 10
                                color: Theme.colors.textDim
                                wrapMode: Text.WrapAnywhere
                                lineHeight: 1.4
                            }
                            ControlButton {
                                visible: !deviceCard.modelData.managed
                                label: "Enable control"
                                icon: "settings_input_antenna"
                                busy: deviceCard.busy
                                enabled: NetworkService.available
                                onClicked: NetworkService.setDeviceManaged(deviceCard.modelData.device, true)
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 88
                    visible: NetworkService.available && NetworkService.interfaces.length === 0 && !NetworkService.refreshing
                    color: Theme.popupSurface0
                    radius: 22
                    Text {
                        anchors.centerIn: parent
                        text: "No network interfaces found"
                        color: Theme.colors.textDim
                        font.family: Theme.textFamily
                        font.pixelSize: 12
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: NetworkService.hasWifi && NetworkService.wifiEnabled
                    ControlSectionHeader {
                        Layout.fillWidth: true
                        title: "Nearby networks"
                        subtitle: NetworkService.scanning ? "Looking for networks…" : !NetworkService.hasManagedWifi ? "Enable control on a Wi-Fi adapter to scan" : NetworkService.wifiNetworks.length + " networks available"
                    }
                    ControlButton {
                        icon: "radar"
                        label: "Scan"
                        busy: NetworkService.scanning
                        enabled: NetworkService.available && NetworkService.hasManagedWifi
                        onClicked: NetworkService.scan()
                    }
                }
                Repeater {
                    model: NetworkService.wifiEnabled ? NetworkService.wifiNetworks : []
                    delegate: Rectangle {
                        id: networkCard
                        required property var modelData
                        readonly property bool busy: !!NetworkService.busyDevices[modelData.device || NetworkService.wifiDevice]
                        Layout.fillWidth: true
                        implicitHeight: 68
                        color: Theme.popupSurface0
                        radius: 20
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 13
                            spacing: 10
                            Text {
                                text: networkCard.modelData.signal > 70 ? "wifi" : networkCard.modelData.signal > 35 ? "wifi_2_bar" : "wifi_1_bar"
                                font.family: Theme.iconFamily
                                font.pixelSize: 23
                                color: networkCard.modelData.active ? Theme.colors.mauve : Theme.colors.textDim
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text {
                                    Layout.fillWidth: true
                                    text: networkCard.modelData.ssid
                                    color: Theme.colors.text
                                    font.family: Theme.textFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: (networkCard.modelData.active ? "Connected · " : "") + networkCard.modelData.signal + "% · "
                                        + (networkCard.modelData.security || "Open")
                                        + (NetworkService.wifiDevices.length > 1 ? " · " + networkCard.modelData.device : "")
                                    color: Theme.colors.textDim
                                    font.family: Theme.textFamily
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }
                            ControlButton {
                                label: networkCard.modelData.active ? "Disconnect" : "Connect"
                                busy: networkCard.busy
                                accent: !networkCard.modelData.active
                                onClicked: root.chooseNetwork(networkCard.modelData)
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    visible: NetworkService.hasManagedWifi && NetworkService.wifiEnabled && !NetworkService.scanning && NetworkService.wifiNetworks.length === 0
                    text: "No nearby networks yet. Scan to refresh the list."
                    color: Theme.colors.textDim
                    font.family: Theme.textFamily
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                }
            }
            Rectangle {
                anchors.right: parent.right
                y: scroll.visibleArea.yPosition * scroll.height
                width: 3
                height: Math.max(22, scroll.visibleArea.heightRatio * scroll.height)
                radius: 2
                color: Theme.colors.outline
                opacity: scroll.moving ? 0.55 : 0
                visible: scroll.contentHeight > scroll.height
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
        }
    }
}
