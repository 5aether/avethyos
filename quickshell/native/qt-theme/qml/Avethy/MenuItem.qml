import QtQuick 2.15
import QtQuick.Templates 2.15 as T
import QtQuick.Controls.impl 2.15
T.MenuItem {
    id: control
    readonly property bool emphasized: enabled && (highlighted || hovered || visualFocus || down)
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    padding: 8
    leftPadding: 30
    rightPadding: 24
    spacing: 8
    hoverEnabled: true
    icon.width: 16
    icon.height: 16
    icon.color: !control.enabled ? Theme.menuMuted : control.emphasized ? Theme.primaryText : Theme.text
    contentItem: IconLabel {
        spacing: control.spacing
        mirrored: control.mirrored
        display: control.display
        icon: control.icon
        text: control.text
        font: control.font
        alignment: Qt.AlignLeft
        color: !control.enabled ? Theme.menuMuted : control.emphasized ? Theme.primaryText : Theme.text
    }
    indicator: Text {
        x: control.mirrored ? control.width - width - 8 : 8
        y: (control.height - height) / 2
        text: "✓"
        font.pixelSize: 14
        color: !control.enabled ? Theme.menuMuted : control.emphasized ? Theme.primaryText : Theme.primary
        visible: control.checked
    }
    arrow: Text {
        x: control.mirrored ? 8 : control.width - width - 8
        y: (control.height - height) / 2
        text: control.mirrored ? "‹" : "›"
        font.pixelSize: 18
        color: !control.enabled ? Theme.menuMuted : control.emphasized ? Theme.primaryText : Theme.text
        visible: control.subMenu !== null
    }
    background: Rectangle { radius: 8; color: control.emphasized ? Theme.primary : "transparent" }
}
