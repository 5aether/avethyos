import QtQuick 2.15
import QtQuick.Templates 2.15 as T
import QtQuick.Controls.impl 2.15
T.TextField {
    id: control
    implicitWidth: 200
    implicitHeight: Math.max(32, contentHeight + topPadding + bottomPadding)
    padding: 8
    leftPadding: 10
    rightPadding: 10
    color: enabled ? Theme.text : Theme.disabled.text
    selectionColor: Theme.primary
    selectedTextColor: Theme.primaryText
    placeholderTextColor: Theme.muted
    background: Rectangle {
        radius: 8
        color: Theme.base
        border.color: control.activeFocus ? Theme.primary : Theme.border
    }
    PlaceholderText {
        x: control.leftPadding
        y: control.topPadding
        width: control.width - control.leftPadding - control.rightPadding
        height: control.height - control.topPadding - control.bottomPadding
        text: control.placeholderText
        font: control.font
        color: control.placeholderTextColor
        verticalAlignment: control.verticalAlignment
        visible: !control.length && !control.preeditText && (!control.activeFocus || control.horizontalAlignment !== Qt.AlignHCenter)
        elide: Text.ElideRight
    }
}
