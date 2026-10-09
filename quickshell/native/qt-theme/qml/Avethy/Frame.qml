import QtQuick 2.15
import QtQuick.Templates 2.15 as T
T.Frame {
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
    padding: 12
    background: Rectangle { color: "transparent"; radius: 8; border.color: Theme.border }
}
