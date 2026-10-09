import QtQuick 2.15
import QtQuick.Templates 2.15 as T
T.ToolTip {
    id: control
    x: parent ? (parent.width - implicitWidth) / 2 : 0
    y: -implicitHeight - 4
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
    margins: 6
    padding: 8
    horizontalPadding: 10
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent | T.Popup.CloseOnReleaseOutsideParent
    contentItem: Text {
        text: control.text
        font: control.font
        color: Theme.text
        wrapMode: Text.WordWrap
    }
    background: Rectangle { radius: 8; color: Theme.floating; border.color: Theme.border }
}
