import QtQuick
import QtQuick.Layouts
import "../components"
import "../widgets"

Item {
    id: root
    property bool active: true
    property string forgetAddress: ""
    implicitHeight: 440

    onActiveChanged: {
        if (active) BluetoothService.refresh();
        else {
            forgetAddress = "";
            if (BluetoothService.scanRequested) BluetoothService.setScanning(false);
        }
    }
    Component.onCompleted: if (active) BluetoothService.refresh()

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 76
            radius: 22
            color: Theme.popupSurface1
            RowLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: 15
                    color: BluetoothService.powered ? Theme.colors.mauve : Theme.popupSurface2
                    Text {
                        anchors.centerIn: parent
                        text: BluetoothService.powered ? "bluetooth" : "bluetooth_disabled"
                        font.family: Theme.iconFamily
                        font.pixelSize: 24
                        color: BluetoothService.powered ? Theme.colors.crust : Theme.colors.textDim
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: !BluetoothService.available ? "Bluetooth unavailable"
                            : BluetoothService.powerBusy ? "Turning Bluetooth " + (BluetoothService.powerTarget ? "on…" : "off…")
                            : BluetoothService.powered ? "Bluetooth is on" : "Bluetooth is off"
                        font.family: Theme.textFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Theme.colors.text
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: BluetoothService.connectedDevices.length
                            ? BluetoothService.connectedDevices.length + " connected · " + BluetoothService.adapterName
                            : BluetoothService.blocked ? "Blocked by the hardware switch"
                            : BluetoothService.available ? BluetoothService.adapterName : "Connect a Bluetooth adapter to get started"
                        font.family: Theme.textFamily
                        font.pixelSize: 10
                        color: Theme.colors.textDim
                        elide: Text.ElideRight
                    }
                }
                ControlSwitch {
                    checked: BluetoothService.powered
                    label: "Bluetooth power"
                    enabled: BluetoothService.available && !BluetoothService.powerBusy
                    onToggled: value => BluetoothService.setPowered(value)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: BluetoothService.message.length > 0
            implicitHeight: feedbackRow.implicitHeight + 18
            radius: 16
            color: BluetoothService.messageIsError
                ? Qt.rgba(Theme.colors.red.r, Theme.colors.red.g, Theme.colors.red.b, 0.10)
                : Theme.popupSurface0
            RowLayout {
                id: feedbackRow
                anchors.fill: parent
                anchors.margins: 9
                spacing: 8
                Text {
                    text: BluetoothService.messageIsError ? "info" : "check_circle"
                    font.family: Theme.iconFamily
                    font.pixelSize: 17
                    color: BluetoothService.messageIsError ? Theme.colors.red : Theme.colors.mauve
                }
                Text {
                    Layout.fillWidth: true
                    text: BluetoothService.message
                    font.family: Theme.textFamily
                    font.pixelSize: 10
                    color: BluetoothService.messageIsError ? Theme.colors.red : Theme.colors.textDim
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                ControlButton {
                    icon: "close"
                    implicitHeight: 28
                    implicitWidth: 28
                    Accessible.name: "Dismiss Bluetooth message"
                    onClicked: BluetoothService.clearMessage()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            ControlSectionHeader {
                Layout.fillWidth: true
                title: "Your devices"
                subtitle: BluetoothService.scanning ? "Finding nearby devices…" : "Connect, disconnect, or manage each device"
            }
            ControlButton {
                icon: BluetoothService.scanning ? "stop" : "bluetooth_searching"
                label: BluetoothService.scanning ? "Stop" : "Scan"
                accent: BluetoothService.scanning
                enabled: BluetoothService.powered && !BluetoothService.powerBusy
                onClicked: BluetoothService.setScanning(!BluetoothService.scanning)
            }
        }

        Flickable {
            id: devicesView
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: deviceSections.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: deviceSections
                width: devicesView.width
                spacing: 9

                SectionLabel {
                    Layout.fillWidth: true
                    visible: BluetoothService.connectedDevices.length > 0
                    label: "CONNECTED"
                    count: BluetoothService.connectedDevices.length
                }
                Repeater {
                    model: BluetoothService.connectedDevices
                    delegate: DeviceCard { required property var modelData; Layout.fillWidth: true; device: modelData }
                }
                SectionLabel {
                    Layout.fillWidth: true
                    label: "SAVED DEVICES"
                    count: BluetoothService.savedDevices.length
                }
                Repeater {
                    model: BluetoothService.savedDevices
                    delegate: DeviceCard { required property var modelData; Layout.fillWidth: true; device: modelData }
                }
                EmptyHint {
                    Layout.fillWidth: true
                    visible: BluetoothService.savedDevices.length === 0 && BluetoothService.connectedDevices.length === 0
                    icon: "devices"
                    title: "No saved devices yet"
                    subtitle: "Pair your headphones, keyboard, or other accessories."
                }
                SectionLabel {
                    Layout.fillWidth: true
                    label: "NEARBY DEVICES"
                    count: BluetoothService.discoveredDevices.length
                }
                Repeater {
                    model: BluetoothService.discoveredDevices
                    delegate: DeviceCard { required property var modelData; Layout.fillWidth: true; device: modelData }
                }
                EmptyHint {
                    Layout.fillWidth: true
                    visible: BluetoothService.discoveredDevices.length === 0
                    icon: BluetoothService.scanning ? "bluetooth_searching" : "radar"
                    title: !BluetoothService.powered ? "Turn on Bluetooth to discover devices"
                        : BluetoothService.scanning ? "Looking for nearby devices" : "Ready to find something new"
                    subtitle: BluetoothService.powered
                        ? "Put your accessory in pairing mode, then scan."
                        : "Your saved devices will stay here."
                }
                Item { Layout.preferredHeight: 2 }
            }
        }
    }

    component SectionLabel: RowLayout {
        property string label: ""
        property int count: 0
        spacing: 6
        Text {
            Layout.fillWidth: true
            text: label
            font.family: Theme.textFamily
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 1.1
            color: Theme.colors.textDim
        }
        Text {
            text: count
            font.family: Theme.textFamily
            font.pixelSize: 10
            color: Theme.colors.textDim
        }
    }

    component EmptyHint: Rectangle {
        property string icon: "bluetooth"
        property string title: ""
        property string subtitle: ""
        implicitHeight: emptyContent.implicitHeight + 28
        radius: 20
        color: Theme.popupSurface0
        RowLayout {
            id: emptyContent
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            Text {
                text: icon
                font.family: Theme.iconFamily
                font.pixelSize: 28
                color: Theme.colors.textDim
                opacity: 0.65
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: title
                    font.family: Theme.textFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.colors.text
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    text: subtitle
                    font.family: Theme.textFamily
                    font.pixelSize: 10
                    color: Theme.colors.textDim
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    component DeviceCard: Rectangle {
        id: card
        required property var device
        readonly property var action: BluetoothService.actions[device.address] || null
        readonly property var prompt: action ? action.prompt : null
        readonly property string error: BluetoothService.deviceErrors[device.address] || ""
        readonly property bool forgetConfirm: root.forgetAddress === device.address
        readonly property string actionLabel: action
            ? action.phase === "pair" ? "Pairing…" : action.phase === "trust" ? "Saving…"
            : action.phase === "disconnect" ? "Disconnecting…" : action.phase === "remove" ? "Forgetting…" : "Connecting…"
            : device.connected ? "Connected" : device.blocked ? "Blocked" : device.paired ? "Saved · Ready to connect" : "Available to pair"
        implicitHeight: deviceContent.implicitHeight + 24
        radius: 20
        color: device.connected ? Theme.popupSurface1 : Theme.popupSurface0
        border.width: device.connected ? 1 : 0
        border.color: Qt.rgba(Theme.colors.mauve.r, Theme.colors.mauve.g, Theme.colors.mauve.b, 0.25)

        ColumnLayout {
            id: deviceContent
            anchors.fill: parent
            anchors.margins: 12
            spacing: 9
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 13
                    color: device.connected ? Theme.colors.mauve : Theme.popupSurface2
                    Text {
                        anchors.centerIn: parent
                        text: BluetoothService.iconFor(device)
                        font.family: Theme.iconFamily
                        font.pixelSize: 21
                        color: device.connected ? Theme.colors.crust : Theme.colors.textDim
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: device.name
                        font.family: Theme.textFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.colors.text
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        Text {
                            Layout.fillWidth: true
                            text: card.actionLabel
                            font.family: Theme.textFamily
                            font.pixelSize: 9
                            color: device.connected ? Theme.colors.mauve : Theme.colors.textDim
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: device.battery >= 0
                            text: device.battery + "%"
                            font.family: Theme.textFamily
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: device.battery <= 15 ? Theme.colors.red : Theme.colors.mauve
                        }
                    }
                }
                ControlButton {
                    label: card.action ? "" : device.connected ? "Disconnect" : device.paired ? "Connect" : "Pair"
                    icon: card.action ? "" : device.connected ? "" : "add_link"
                    busy: !!card.action
                    accent: !device.connected && !card.action
                    implicitHeight: 32
                    enabled: BluetoothService.powered && !device.blocked && !BluetoothService.powerBusy
                    onClicked: BluetoothService.activate(device)
                }
                ControlButton {
                    visible: device.paired && !card.action
                    icon: "more_horiz"
                    implicitWidth: 30
                    implicitHeight: 32
                    Accessible.name: "Manage " + device.name
                    onClicked: root.forgetAddress = card.forgetConfirm ? "" : device.address
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !device.paired || card.forgetConfirm
                text: device.address
                font.family: Theme.textFamily
                font.pixelSize: 9
                color: Theme.colors.textDim
                opacity: 0.7
            }
            Text {
                Layout.fillWidth: true
                visible: card.error.length > 0
                text: card.error
                font.family: Theme.textFamily
                font.pixelSize: 10
                color: Theme.colors.red
                wrapMode: Text.Wrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: card.forgetConfirm
                spacing: 7
                Text {
                    Layout.fillWidth: true
                    text: "Forget this device? You will need to pair it again."
                    font.family: Theme.textFamily
                    font.pixelSize: 10
                    color: Theme.colors.textDim
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    ControlButton { label: "Keep"; implicitHeight: 30; onClicked: root.forgetAddress = "" }
                    ControlButton {
                        label: "Forget"
                        icon: "link_off"
                        danger: true
                        implicitHeight: 30
                        onClicked: { root.forgetAddress = ""; BluetoothService.forget(device); }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !!card.prompt
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: card.prompt ? card.prompt.message : ""
                    font.family: Theme.textFamily
                    font.pixelSize: 10
                    color: Theme.colors.textDim
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: !!card.prompt && card.prompt.code.length > 0
                    text: card.prompt ? card.prompt.code : ""
                    font.family: Theme.textFamily
                    font.pixelSize: 25
                    font.weight: Font.DemiBold
                    font.letterSpacing: 5
                    color: Theme.colors.mauve
                    horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    visible: !!card.prompt && (card.prompt.kind === "pin" || card.prompt.kind === "passkey")
                    radius: 12
                    color: Theme.popupSurface2
                    border.width: pairingInput.activeFocus ? 1 : 0
                    border.color: Theme.colors.mauve
                    TextInput {
                        id: pairingInput
                        anchors.fill: parent
                        anchors.margins: 10
                        font.family: Theme.textFamily
                        font.pixelSize: 12
                        color: Theme.colors.text
                        selectionColor: Theme.colors.mauve
                        selectedTextColor: Theme.colors.crust
                        maximumLength: card.prompt && card.prompt.kind === "passkey" ? 6 : 16
                        inputMethodHints: card.prompt && card.prompt.kind === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
                        selectByMouse: true
                        Accessible.name: "Bluetooth pairing code"
                        onAccepted: if (text.length) BluetoothService.answerPairing(device.address, text)
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    ControlButton {
                        label: "Cancel"
                        implicitHeight: 30
                        onClicked: BluetoothService.cancelAction(device.address)
                    }
                    ControlButton {
                        visible: !!card.prompt && card.prompt.kind !== "display"
                        label: card.prompt && card.prompt.kind === "confirm" ? "Confirm" : "Pair"
                        accent: true
                        implicitHeight: 30
                        enabled: !!card.prompt && (card.prompt.kind === "confirm" || pairingInput.text.length > 0)
                        onClicked: BluetoothService.answerPairing(device.address,
                            card.prompt.kind === "confirm" ? "yes" : pairingInput.text)
                    }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                visible: !!card.action && !card.prompt
                ControlButton {
                    label: "Cancel"
                    implicitHeight: 28
                    onClicked: BluetoothService.cancelAction(device.address)
                }
            }
        }
    }
}
