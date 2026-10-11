import QtQuick
import Quickshell

// Neither Region nor TransformWatcher observes a Translate/Scale object list.
// Refresh after motion bindings settle so the native input mask follows it.
Region {
    id: region

    property var motion: null
    property Item surfaceItem: null
    property real revealHeight: surfaceItem?.revealedHeight ?? surfaceItem?.height ?? 0
    // Keep the native input mask within the part of the surface that exists.
    // This child also inherits the popup's transforms in floating mode.
    property Item inputItem: Item {
        parent: region.surfaceItem
        width: region.surfaceItem?.width ?? 0
        height: region.revealHeight
    }
    item: inputItem
    readonly property real progress: motion?.progress ?? 0
    readonly property real settle: motion?.settle ?? 1
    onProgressChanged: Qt.callLater(region.changed)
    onSettleChanged: Qt.callLater(region.changed)

    property TransformWatcher watcher: TransformWatcher {
        a: region.item
        b: region.item?.QsWindow.window?.contentItem ?? null
        onTransformChanged: region.changed()
    }
}
