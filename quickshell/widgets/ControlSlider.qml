import QtQuick
import Quickshell.Widgets
import "../components"

Item {
    id: root
    property real minimum: 0
    property real maximum: 1
    property real step: 0.01
    property real value: 0
    property color accent: Theme.colors.mauve
    property string icon: ""
    property string valueText: Math.round(position * 100) + "%"
    property string label: "Slider"
    readonly property bool dragging: enabled && pointer.pressed
    readonly property bool hovered: enabled && pointer.containsMouse
    readonly property real position: maximum > minimum
        ? Math.max(0, Math.min(1, (value - minimum) / (maximum - minimum))) : 0
    readonly property color ink: accent.r * 0.299 + accent.g * 0.587 + accent.b * 0.114 > 0.58
        ? "#202024" : "#ffffff"
    signal moved(real newValue)
    signal committed(real newValue)
    implicitHeight: 42
    implicitWidth: 160
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: label
    Accessible.description: valueText

    function snappedValue(raw) {
        const interval = step > 0 ? step : (maximum - minimum) / 100;
        return Math.max(minimum, Math.min(maximum, minimum + Math.round((raw - minimum) / interval) * interval));
    }
    function valueAt(x) {
        const inset = height / 2;
        return snappedValue(minimum + Math.max(0, Math.min(1,
            (x - inset) / Math.max(1, width - 2 * inset))) * (maximum - minimum));
    }
    function adjust(delta) {
        const next = snappedValue(value + delta);
        moved(next);
        committed(next);
    }
    Keys.onLeftPressed: adjust(-step)
    Keys.onRightPressed: adjust(step)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) { moved(minimum); committed(minimum); event.accepted = true; }
        else if (event.key === Qt.Key_End) { moved(maximum); committed(maximum); event.accepted = true; }
    }

    ClippingRectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.hovered ? Theme.popupSurface2 : Theme.popupSurface1
        border.width: root.activeFocus ? 2 : 0
        border.color: root.accent
        contentUnderBorder: true
        Rectangle {
            id: fill
            height: parent.height
            width: root.position === 0 ? 0 : parent.height + root.position * (parent.width - parent.height)
            radius: height / 2
            color: root.accent
            Behavior on width { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        Text {
            x: 13
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: fill.width > x + width / 2 ? root.ink : Theme.colors.textDim
            font.family: Theme.iconFamily
            font.pixelSize: 20
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            text: root.valueText
            color: fill.width > x + width / 2 ? root.ink : Theme.colors.text
            font.family: Theme.textFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
            visible: !root.dragging || root.width > 200
        }
        Rectangle {
            x: Math.max(12, Math.min(parent.width - 17, fill.width - 13))
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: root.dragging ? 23 : 17
            radius: 1.5
            color: root.position > 0 ? root.ink : Theme.colors.textDim
            opacity: root.dragging || root.hovered ? 0.85 : 0
            Behavior on height { NumberAnimation { duration: 140 } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: mouse => { root.forceActiveFocus(); root.moved(root.valueAt(mouse.x)); }
        onPositionChanged: mouse => { if (pressed) root.moved(root.valueAt(mouse.x)); }
        onReleased: root.committed(root.value)
        onWheel: wheel => {
            const delta = wheel.angleDelta.y || wheel.angleDelta.x;
            if (delta) root.adjust((delta > 0 ? 1 : -1) * root.step);
            wheel.accepted = true;
        }
    }
}
