import QtQuick
import Quickshell
import "../components"
import "../widgets"

FocusScope {
    id: root

    property var entry: null
    // Keep the last menu intact while it rolls away after dismissal.
    property var displayedEntry: null
    property point requestedPosition: Qt.point(0, 0)
    readonly property var rows: {
        if (!displayedEntry)
            return [];
        const result = [{ name: qsTr("Open"), icon: "", action: null }];
        for (const action of displayedEntry.actions) {
            if (action.command.length > 0)
                result.push({ name: action.name || action.id, icon: action.icon, action: action });
        }
        return result;
    }

    signal triggered(var action)
    signal dismissed()

    function open(app, position): void {
        requestedPosition = position;
        entry = app;
        options.currentIndex = 0;
        options.positionViewAtBeginning();
        forceActiveFocus();
    }

    onEntryChanged: {
        if (entry)
            displayedEntry = entry;
    }

    visible: motion.active
    enabled: entry !== null
    transform: [
        Translate { y: motion.offsetY },
        Scale {
            origin.x: 0
            origin.y: 0
            xScale: motion.scaleX
            yScale: motion.scaleY
        }
    ]

    PopupMotion {
        id: motion
        opened: root.entry !== null
        attached: false
        distance: 16
        onClosed: root.displayedEntry = null
    }

    implicitWidth: {
        let widest = metrics.advanceWidth(displayedEntry ? displayedEntry.name : "");
        for (const row of rows)
            widest = Math.max(widest, metrics.advanceWidth(row.name) + 24);
        return Math.max(220, Math.min(320, widest + 32));
    }
    implicitHeight: 52 + rows.length * 34 + (rows.length > 1 ? 9 : 0)
    width: Math.min(implicitWidth, parent.width - 16)
    height: Math.min(implicitHeight, parent.height - 16)
    // This lives above the launcher in its existing window, so a menu at the
    // edge of the app grid is not clipped and keeps the same focus grab.
    x: Math.max(8, Math.min(requestedPosition.x, parent.width - width - 8))
    y: Math.max(8, Math.min(requestedPosition.y, parent.height - height - 8))

    FontMetrics {
        id: metrics
        font.family: Theme.textFamily
        font.pixelSize: 12
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.popupSurface2
        border.width: 1
        border.color: Qt.rgba(Theme.colors.text.r, Theme.colors.text.g,
                              Theme.colors.text.b, 0.14)
    }

    // Absorb clicks on the heading, padding and separators.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Text {
        x: 16
        y: 12
        width: parent.width - 32
        text: root.displayedEntry ? root.displayedEntry.name : ""
        font.family: Theme.textFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: Theme.colors.textDim
        elide: Text.ElideRight
    }

    Rectangle {
        x: 12
        y: 36
        width: parent.width - 24
        height: 1
        color: Theme.popupSurface1
    }

    ListView {
        id: options
        anchors.fill: parent
        anchors.topMargin: 44
        anchors.bottomMargin: 8
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        clip: true
        focus: true
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel { values: root.rows }
        currentIndex: 0
        highlightMoveDuration: 0

        delegate: Item {
            id: option
            required property var modelData
            required property int index
            readonly property int topGap: index === 1 ? 9 : 0
            width: options.width
            height: 34 + topGap

            Rectangle {
                visible: option.index === 1
                x: 8
                y: 4
                width: parent.width - 16
                height: 1
                color: Theme.popupSurface1
            }

            Rectangle {
                y: option.topGap
                width: parent.width
                height: 34
                radius: Math.max(4, Theme.radius - 4)
                color: options.currentIndex === option.index
                    ? Theme.popupSurface0 : "transparent"

                Image {
                    id: actionIcon
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    source: option.modelData.icon
                        ? IconThemeService.resolve(option.modelData.icon) : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                }

                Text {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: option.index === 0 ? "open_in_new" : "chevron_right"
                    font.family: Theme.iconFamily
                    font.pixelSize: 16
                    color: Theme.colors.blue
                    visible: !actionIcon.visible
                }

                Text {
                    x: 32
                    width: parent.width - 40
                    anchors.verticalCenter: parent.verticalCenter
                    text: option.modelData.name
                    font.family: Theme.textFamily
                    font.pixelSize: 12
                    color: Theme.colors.text
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: options.currentIndex = option.index
                    onPositionChanged: options.currentIndex = option.index
                    onClicked: root.triggered(option.modelData.action)
                }
            }
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            root.dismissed();
            break;
        case Qt.Key_Up:
            options.currentIndex = (options.currentIndex + options.count - 1) % options.count;
            break;
        case Qt.Key_Down:
            options.currentIndex = (options.currentIndex + 1) % options.count;
            break;
        case Qt.Key_Home:
            options.currentIndex = 0;
            break;
        case Qt.Key_End:
            options.currentIndex = options.count - 1;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (options.currentIndex >= 0 && options.currentIndex < root.rows.length)
                root.triggered(root.rows[options.currentIndex].action);
            break;
        default:
            event.accepted = false;
            return;
        }
        options.positionViewAtIndex(options.currentIndex, ListView.Contain);
        event.accepted = true;
    }
}
