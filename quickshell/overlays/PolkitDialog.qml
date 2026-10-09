import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../components"
import "../widgets"

// An unanchored layer-shell window is centered on the whole output. Ignore
// exclusive zones so the bar does not shift the dialog below screen center.
PanelWindow {
    id: root

    readonly property int shadowPadding: 16
    property bool submitting: false
    // Keep the last request visible during the closing animation.
    property string requestMessage: "Authentication required"
    property string inputPrompt: "Password"
    property string supplementaryMessage: ""
    property bool messageIsError: false
    readonly property bool responseRequired: PolkitManager.pending
        && (PolkitManager.flow?.isResponseRequired ?? false)
    readonly property bool canSubmit: responseRequired && !submitting
    readonly property bool responseVisible: PolkitManager.flow?.responseVisible ?? false
    readonly property real maximumMessageHeight: Math.max(48,
        (screen ? screen.height : 1080) - header.implicitHeight
        - passwordSection.implicitHeight - footer.implicitHeight
        - content.spacing * 3 - 48 - shadowPadding * 2 - 48)

    PopupMotion {
        id: dialogMotion
        opened: PolkitManager.pending
        attached: false
        distance: 24
    }

    visible: dialogMotion.active
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:polkit"
    WlrLayershell.keyboardFocus: PolkitManager.pending
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    implicitWidth: Math.min(520 + shadowPadding * 2,
                           (screen ? screen.width : 1920) - 32)
    implicitHeight: card.height + shadowPadding * 2
    mask: Region { item: card }

    function updateDetails() {
        if (!PolkitManager.pending)
            return;
        const flow = PolkitManager.flow;
        requestMessage = flow.message || "Authentication required";
        inputPrompt = flow.inputPrompt || "Password";
        supplementaryMessage = flow.supplementaryMessage
            || (PolkitManager.failed ? "Authentication failed. Please try again." : "");
        messageIsError = PolkitManager.failed || flow.supplementaryIsError;
    }

    function focusResponse() {
        if (root.visible && root.canSubmit)
            passField.forceActiveFocus();
    }

    function updatePending() {
        passField.text = "";
        submitting = false;
        if (PolkitManager.pending) {
            updateDetails();
            // Choose the active output once, so moving the pointer between
            // monitors while typing cannot move the authentication dialog.
            const monitorName = Hyprland.focusedMonitor?.name;
            root.screen = Quickshell.screens.find(s => s.name === monitorName)
                || Quickshell.screens[0] || null;
            messageViewport.contentY = 0;
            Qt.callLater(() => {
                root.focusResponse();
            });
        }
    }

    Component.onCompleted: {
        if (PolkitManager.pending)
            updatePending();
    }
    onBackingWindowVisibleChanged: if (backingWindowVisible) Qt.callLater(focusResponse)

    Connections {
        target: PolkitManager
        function onPendingChanged() { root.updatePending(); }
        function onFailedChanged() { root.updateDetails(); }
    }

    Connections {
        target: PolkitManager.flow
        function onInputPromptChanged() { root.updateDetails(); }
        function onSupplementaryMessageChanged() { root.updateDetails(); }
        function onSupplementaryIsErrorChanged() { root.updateDetails(); }
        function onIsResponseRequiredChanged() {
            if (PolkitManager.flow?.isResponseRequired) {
                root.submitting = false;
                passField.text = "";
                Qt.callLater(root.focusResponse);
            }
        }
        function onAuthenticationFailed() {
            root.submitting = false;
            passField.text = "";
            root.updateDetails();
            Qt.callLater(root.focusResponse);
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: true
        transform: [
            Translate { y: dialogMotion.offsetY },
            Scale {
                origin.x: root.width / 2
                origin.y: root.height / 2
                xScale: dialogMotion.scaleX
                yScale: dialogMotion.scaleY
            }
        ]

        Keys.onEscapePressed: PolkitManager.cancel()

        Rectangle {
            id: shadowSource
            anchors.fill: card
            radius: card.radius
            color: "black"
            visible: false
        }

        DropShadow {
            anchors.fill: shadowSource
            source: shadowSource
            horizontalOffset: 0
            verticalOffset: 4
            radius: 16
            samples: 33
            color: "#38000000"
            transparentBorder: true
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: root.width - root.shadowPadding * 2
            height: content.implicitHeight + 48
            radius: 20
            color: Qt.rgba(Theme.colors.base.r, Theme.colors.base.g,
                           Theme.colors.base.b, 0.68)
            border.width: 1
            border.color: Qt.rgba(Theme.colors.outline.r, Theme.colors.outline.g,
                                  Theme.colors.outline.b, 0.22)

            ColumnLayout {
                id: content
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 20

                RowLayout {
                    id: header
                    Layout.fillWidth: true
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: Theme.radius
                        color: Theme.popupSurface0

                        Text {
                            anchors.centerIn: parent
                            text: "lock"
                            font.family: Theme.iconFamily
                            font.pixelSize: 26
                            color: Theme.colors.mauve
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: "Authentication required"
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: Theme.colors.text
                            font.family: Theme.textFamily
                            font.pixelSize: 21
                            font.weight: Font.DemiBold
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "System permission"
                            color: Theme.colors.textDim
                            font.family: Theme.textFamily
                            font.pixelSize: 13
                        }
                    }
                }

                Flickable {
                    id: messageViewport
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(messageContent.implicitHeight,
                                                     root.maximumMessageHeight)
                    contentWidth: width
                    contentHeight: messageContent.implicitHeight
                    flickableDirection: Flickable.VerticalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        visible: messageViewport.contentHeight > messageViewport.height + 1
                        contentItem: Rectangle {
                            implicitWidth: 3
                            radius: 2
                            color: Theme.colors.textDim
                            opacity: 0.45
                        }
                        background: Item {}
                    }

                    ColumnLayout {
                        id: messageContent
                        width: messageViewport.width - 10
                        spacing: 12

                        Text {
                            Layout.fillWidth: true
                            text: root.requestMessage
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: Theme.colors.text
                            font.family: Theme.textFamily
                            font.pixelSize: 15
                            lineHeight: 1.25
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: statusText.implicitHeight + 24
                            visible: root.supplementaryMessage.length > 0
                            radius: Theme.radius
                            color: root.messageIsError
                                ? Qt.rgba(Theme.colors.red.r, Theme.colors.red.g,
                                          Theme.colors.red.b, 0.10)
                                : Theme.popupSurface0

                            Text {
                                id: statusText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                text: root.supplementaryMessage
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: root.messageIsError ? Theme.colors.red : Theme.colors.textDim
                                font.family: Theme.textFamily
                                font.pixelSize: 13
                                lineHeight: 1.2
                            }
                        }
                    }
                }

                ColumnLayout {
                    id: passwordSection
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: root.inputPrompt.trim()
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Theme.colors.textDim
                        font.family: Theme.textFamily
                        font.pixelSize: 13
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: Theme.radius
                        color: Theme.popupSurface0
                        border.width: 1
                        border.color: passField.activeFocus ? Theme.colors.mauve
                            : (root.messageIsError ? Theme.colors.red : Theme.popupSurface2)

                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: "key"
                            color: passField.activeFocus ? Theme.colors.mauve : Theme.colors.textDim
                            font.family: Theme.iconFamily
                            font.pixelSize: 20
                        }

                        Text {
                            anchors.fill: passField
                            verticalAlignment: Text.AlignVCenter
                            text: root.responseVisible ? "Enter your response" : "Enter your password"
                            color: Theme.colors.textDim
                            opacity: 0.65
                            font.family: Theme.textFamily
                            font.pixelSize: 15
                            visible: passField.text.length === 0
                        }

                        TextInput {
                            id: passField
                            anchors.fill: parent
                            anchors.leftMargin: 44
                            anchors.rightMargin: 14
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.colors.text
                            selectionColor: Theme.colors.mauve
                            selectedTextColor: Theme.colors.crust
                            font.family: Theme.textFamily
                            font.pixelSize: 15
                            clip: true
                            enabled: root.canSubmit
                            activeFocusOnTab: true
                            echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
                            selectByMouse: true
                            inputMethodHints: root.responseVisible ? Qt.ImhNone
                                : Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                            Accessible.name: root.inputPrompt
                            onAccepted: root.attemptSubmit()
                        }
                    }
                }

                RowLayout {
                    id: footer
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        visible: card.width >= 460
                        text: "Esc to cancel"
                        color: Theme.colors.textDim
                        font.family: Theme.textFamily
                        font.pixelSize: 12
                    }

                    Item { Layout.fillWidth: true }

                    ActionButton {
                        label: "Cancel"
                        onClicked: PolkitManager.cancel()
                    }

                    ActionButton {
                        label: root.submitting ? "Authenticating…" : "Authenticate"
                        primary: true
                        enabled: root.canSubmit
                        onClicked: root.attemptSubmit()
                    }
                }
            }
        }
    }

    component ActionButton: Rectangle {
        id: button
        required property string label
        property bool primary: false
        signal clicked()

        implicitWidth: buttonText.implicitWidth + 32
        implicitHeight: 44
        radius: Theme.radius
        activeFocusOnTab: true
        opacity: enabled ? 1 : 0.55
        color: primary ? Theme.colors.mauve
            : (buttonMouse.containsMouse || activeFocus ? Theme.popupSurface2 : Theme.popupSurface1)
        border.width: activeFocus ? 1 : 0
        border.color: primary ? Theme.colors.text : Theme.colors.mauve
        scale: buttonMouse.pressed ? 0.98 : 1

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 100 } }

        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: clicked()
        Keys.onSpacePressed: clicked()
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()

        Text {
            id: buttonText
            anchors.centerIn: parent
            text: button.label
            color: button.primary ? Theme.colors.crust : Theme.colors.text
            font.family: Theme.textFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    function attemptSubmit() {
        if (!canSubmit)
            return;
        submitting = true;
        PolkitManager.submit(passField.text);
        passField.text = "";
    }
}
