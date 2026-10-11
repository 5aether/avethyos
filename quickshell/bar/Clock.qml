import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../components"
import "../widgets"
import "../modules/format.js" as Fmt

Rectangle {
    id: root
    property date now: systemClock.date
    property date shownMonth: new Date(now.getFullYear(), now.getMonth(), 1)
    property bool popupOpen: false

    function togglePopup(): void {
        if (!root.popupOpen)
            shownMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        root.popupOpen = !root.popupOpen;
    }

    PopupFocus {
        popupWindow: popup
        opened: root.popupOpen
        dismissAction: function() { root.popupOpen = false; }
    }
    PopupMotion {
        id: popupMotion
        opened: root.popupOpen
        distance: popupFrame.height
    }

    // Resolves an icon to a loadable URL.
    //
    // IconImage.source is a plain alias to Image.source: it takes a URL and does
    // NOT resolve freedesktop icon names, so handing it a bare name like
    // "vesktop" would resolve it as a relative path against IconImage.qml's own
    // qrc directory. Quickshell.iconPath() is what turns a themed name into a
    // real URL, so it is used for names, while an absolute path or an existing
    // URL is passed through untouched.
    function iconSource(value) {
        const icon = String(value || "");
        if (!icon.length)
            return "";
        // A real path, or anything already carrying a scheme (file://, ...).
        if (icon.startsWith("/") || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(icon))
            return icon;
        return IconThemeService.resolve(icon, "application-x-executable");
    }

    width: 82
    height: 30
    radius: Theme.radius
    color: root.popupOpen || clockMouse.containsMouse ? Theme.popupSurface1 : "transparent"

    // Days in the month currently shown. Computed once and read by both the
    // grid and the day buttons instead of rebuilding a Date per cell.
    readonly property int daysInShownMonth: new Date(
        shownMonth.getFullYear(), shownMonth.getMonth() + 1, 0).getDate()

    // getDay() is 0 = Sunday; shift so the grid starts on Monday.
    readonly property int firstWeekday: (new Date(
        shownMonth.getFullYear(), shownMonth.getMonth(), 1).getDay() + 6) % 7

    function calendarDay(index) { return index - root.firstWeekday + 1; }
    function sameDay(day) {
        return day === now.getDate() && shownMonth.getMonth() === now.getMonth()
               && shownMonth.getFullYear() === now.getFullYear();
    }

    Behavior on color { ColorAnimation { duration: 140 } }

    Text {
        id: clockText
        anchors.centerIn: parent
        color: Theme.colors.text
        font.pixelSize: 13
        font.bold: true
        font.family: Theme.textFamily
    }

    MouseArea {
        id: clockMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.togglePopup()
    }

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }
    Binding { target: clockText; property: "text"; value: Fmt.formatTime(root.now) }

    // Invisible full-screen layer to catch clicks outside the popup
    PanelWindow {
        id: dismissLayer
        screen: popup.screen
        visible: root.popupOpen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:clock-dismiss"
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
        id: glassBackdrop
        visible: popupMotion.active
        screen: popup.screen
        anchors.top: true
        margins.top: popup.margins.top
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:popup-backdrop"
        implicitWidth: popup.width
        implicitHeight: popup.height
        color: "transparent"
        mask: Region {}

        AttachedGlass {
            screen: popup.screen
            active: popupMotion.active
            sourceWindow: glassBackdrop
            joinProgress: popupMotion.joinProgress
            revealProgress: popupMotion.expansionProgress
            flowProgress: popupMotion.progress
            flowAnchor: Qt.vector2d(0.5, 0)
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: popup.height - 8
            cornerRadius: popup.cornerRadius
            attachRightEdge: false
            color: Theme.barBackground
            transform: [
                Translate { y: popupMotion.offsetY },
                Scale {
                    origin.x: popupFrame.width / 2
                    origin.y: 0
                    xScale: popupMotion.scaleX
                    yScale: popupMotion.scaleY
                }
            ]
        }
    }

    PanelWindow {
        id: popup
        readonly property int cornerRadius: 20
        visible: popupMotion.active
        screen: root.QsWindow.window?.screen ?? null
        anchors.top: true
        margins.top: OverlayService.topMargin(screen)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:clock"
        focusable: root.popupOpen
        implicitWidth: 720 + 2 * cornerRadius
        // Fixed height that fits the largest month (6 week rows) with a little
        // breathing room: margins 28 + header 30 + spacing 10 + weekday row 24
        // + row spacing 6 + 6 rows of 30 + padding 18.
        implicitHeight: 329 + cornerRadius + 8
        color: "transparent"
        mask: PopupRegion { surfaceItem: popupFrame; motion: popupMotion }

        AttachedPanel {
            id: popupFrame
            joinProgress: popupMotion.joinProgress
            revealProgress: popupMotion.expansionProgress
            contentOpacity: popupMotion.contentOpacity
            flowProgress: popupMotion.progress
            flowAnchor: Qt.vector2d(0.5, 0)
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: popup.height - 8
            enabled: root.popupOpen
            transform: [
                Translate { y: popupMotion.offsetY },
                Scale {
                    origin.x: popupFrame.width / 2
                    origin.y: 0
                    xScale: popupMotion.scaleX
                    yScale: popupMotion.scaleY
                }
            ]
            cornerRadius: popup.cornerRadius
            attachRightEdge: false
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                anchors.leftMargin: 14 + popup.cornerRadius
                anchors.rightMargin: 14 + popup.cornerRadius
                anchors.bottomMargin: 14 + popup.cornerRadius
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 320
                    Layout.fillHeight: true
                    radius: Theme.radius
                    color: Theme.popupSurface0

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            CalendarButton {
                                icon: "chevron_left"
                                onClicked: root.shownMonth = new Date(root.shownMonth.getFullYear(), root.shownMonth.getMonth() - 1, 1)
                            }
                            Text {
                                font.family: Theme.textFamily
                                Layout.fillWidth: true
                                text: Qt.locale().monthName(root.shownMonth.getMonth(), Locale.LongFormat) + " " + root.shownMonth.getFullYear()
                                color: Theme.colors.text
                                font.pixelSize: 15
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                            CalendarButton {
                                icon: "chevron_right"
                                onClicked: root.shownMonth = new Date(root.shownMonth.getFullYear(), root.shownMonth.getMonth() + 1, 1)
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 7
                            rowSpacing: 6
                            columnSpacing: 4

                            Repeater {
                                model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                                delegate: Text {
                                    font.family: Theme.textFamily
                                    required property string modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 24
                                    text: modelData
                                    color: Theme.colors.textDim
                                    font.pixelSize: 10
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Repeater {
                                // 6 rows of 7 always fit any month, so the grid
                                // height never changes while paging.
                                model: 42
                                delegate: Rectangle {
                                    id: dayCell

                                    required property int index
                                    readonly property int day: root.calendarDay(index)
                                    readonly property bool validDay:
                                        day > 0 && day <= root.daysInShownMonth
                                    readonly property bool today: root.sameDay(day)

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    radius: Theme.radius
                                    color: today ? Theme.colors.mauve
                                         : dayMouse.containsMouse && validDay
                                           ? Theme.popupSurface1
                                           : "transparent"

                                    Text {
                                        font.family: Theme.textFamily
                                        anchors.centerIn: parent
                                        text: dayCell.validDay ? dayCell.day : ""
                                        color: dayCell.today
                                               ? Theme.colors.crust : Theme.colors.text
                                        font.pixelSize: 11
                                        font.bold: dayCell.today
                                    }
                                    MouseArea {
                                        id: dayMouse
                                        anchors.fill: parent
                                        enabled: dayCell.validDay
                                        hoverEnabled: true
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radius
                    color: Theme.popupSurface0

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 9

                        RowLayout {
                            Layout.fillWidth: true
                            Text { font.family: Theme.textFamily; Layout.fillWidth: true; text: "Notifications"; color: Theme.colors.text; font.pixelSize: 15; font.bold: true }
                            Rectangle {
                                visible: NotificationManager.historyCount > 0
                                width: 32
                                height: 28
                                radius: Theme.radius
                                color: clearMouse.containsMouse ? Theme.popupSurface2 : Theme.popupSurface1
                                Text { anchors.centerIn: parent; text: "delete_sweep"; color: Theme.colors.textDim; font.family: Theme.iconFamily; font.pixelSize: 17 }
                                MouseArea {
                                    id: clearMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: NotificationManager.dismissAll()
                                }
                            }
                        }

                        ListView {
                            id: notificationList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 7
                            model: NotificationManager.notifications

                            delegate: Rectangle {
                                id: notificationCard
                                required property var modelData
                                width: ListView.view.width
                                // notificationContent is anchored, so its
                                // implicitHeight is 0; size the card from the
                                // text column and the 36px icon instead.
                                height: 20 + Math.max(36, historyText.implicitHeight)
                                radius: Theme.radius
                                color: notificationMouse.containsMouse ? Theme.popupSurface2 : Theme.popupSurface1

                                RowLayout {
                                    id: notificationContent

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    height: parent.height - 20
                                    spacing: 9

                                        ClippingRectangle {
                                            width: 36
                                            height: 36
                                            radius: Theme.radius
                                            color: Theme.popupSurface0

                                            // Same universal priority as the toast:
                                            // notification image/avatar first, app
                                            // icon underneath as fallback.
                                            //
                                            // A plain Image is used because
                                            // root.iconSource() has already
                                            // resolved the name to a URL: passing a
                                            // bare name to IconImage would be read
                                            // as a relative path.
                                            Image {
                                                id: historyIcon
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                source: root.iconSource(
                                                    NotificationManager.primaryAppIcon(
                                                        notificationCard.modelData))
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                                smooth: true
                                                visible: !historyPhoto.visible
                                                        && source.toString().length > 0
                                                        && status === Image.Ready
                                            }

                                            Image {
                                                id: historyPhoto
                                                anchors.fill: parent
                                                anchors.margins: -5
                                                source: NotificationManager.primaryImage(
                                                    notificationCard.modelData)
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                visible: source.toString().length > 0
                                                        && status === Image.Ready
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                visible: !historyIcon.visible && !historyPhoto.visible
                                                text: "notifications"
                                                color: Theme.colors.mauve
                                                font.family: Theme.iconFamily
                                                font.pixelSize: 18
                                            }
                                        }

                                    ColumnLayout {
                                        id: historyText
                                        Layout.fillWidth: true
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                font.family: Theme.textFamily
                                                Layout.fillWidth: true
                                                text: notificationCard.modelData.summary
                                                color: Theme.colors.text
                                                font.pixelSize: 11
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                font.family: Theme.textFamily
                                                text: Qt.formatTime(new Date(notificationCard.modelData.at), "HH:mm")
                                                color: Theme.colors.textDim
                                                font.pixelSize: 9
                                            }
                                        }
                                        Text {
                                            font.family: Theme.textFamily
                                            Layout.fillWidth: true
                                            visible: text.length > 0
                                            text: notificationCard.modelData.body
                                            textFormat: Text.PlainText
                                            color: Theme.colors.textDim
                                            font.pixelSize: 10
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 4
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        text: "close"
                                        color: Theme.colors.textDim
                                        font.family: Theme.iconFamily
                                        font.pixelSize: 16
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: NotificationManager.removeFromHistory(notificationCard.modelData.id)
                                        }
                                    }
                                }

                                MouseArea { id: notificationMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                            }

                            Text {
                                font.family: Theme.textFamily
                                anchors.centerIn: parent
                                visible: notificationList.count === 0
                                text: "No notifications"
                                color: Theme.colors.textDim
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }

    component CalendarButton: Rectangle {
        id: button

        required property string icon
        signal clicked()

        width: 30
        height: 30
        radius: Theme.radius
        color: buttonMouse.containsMouse ? Theme.popupSurface2 : Theme.popupSurface1

        Text {
            id: buttonText
            anchors.centerIn: parent
            text: button.icon
            color: Theme.colors.text
            font.family: Theme.iconFamily
            font.pixelSize: 18
        }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
