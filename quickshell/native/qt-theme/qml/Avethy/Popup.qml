import QtQuick 2.15
import QtQuick.Templates 2.15 as T
T.Popup {
    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)
    padding: 12
    background: Rectangle { color: Theme.floating; radius: 12; border.color: Theme.border }
}
