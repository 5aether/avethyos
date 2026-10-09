import QtQuick 2.15
import QtQuick.Templates 2.15 as T
T.Menu {
    id: control
    implicitWidth: Math.max(200, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
    padding: 6
    margins: 6
    delegate: MenuItem {}
    contentItem: ListView {
        implicitHeight: contentHeight
        model: control.contentModel
        interactive: contentHeight > height
        clip: true
        currentIndex: control.currentIndex
    }
    background: Rectangle { radius: 12; color: Theme.floating; border.color: Theme.border }
}
