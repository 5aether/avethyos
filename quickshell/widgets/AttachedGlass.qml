import QtQuick
import Quickshell
import "../components"

// Keep the caller's geometry in its popup while drawing only its background
// in the bar. Controls and their native input regions stay in the popup.
Item {
    id: root

    property var sourceWindow: root.QsWindow.window
    property var screen: sourceWindow?.screen ?? null
    property bool active: true
    property Item standaloneParent: root.parent

    property color color: Theme.colors.mantle
    property color borderColor: Theme.colors.surface1
    property real cornerRadius: 20
    property bool attachRightEdge: true
    property real borderWidth: 0
    property real edgeSoftness: 2
    property real flowProgress: 1
    property real flowStrength: 0
    property vector2d flowAnchor: Qt.vector2d(1, 0)
    property real joinProgress: 1
    property real revealProgress: 1
    // Optional paint shared with an overlay that replaces this glass tint.
    property Component backgroundContent: null
    readonly property real revealedHeight: Math.min(height, 3 * cornerRadius) * joinProgress
        + Math.max(0, height - 3 * cornerRadius) * revealProgress
    readonly property real bodyLeft: cornerRadius
    readonly property real bodyBottom: height - cornerRadius

    // Layer-shell does not expose its native x/y to QML. These coordinates
    // follow its documented anchor and margin placement in logical pixels.
    property real globalX: {
        if (!sourceWindow || !screen)
            return 0;
        const width = sourceWindow.width || sourceWindow.implicitWidth;
        if (sourceWindow.anchors.left)
            return sourceWindow.margins.left;
        if (sourceWindow.anchors.right)
            return screen.width - width - sourceWindow.margins.right;
        return (screen.width - width + sourceWindow.margins.left
            - sourceWindow.margins.right) / 2;
    }
    property real globalY: sourceWindow?.margins.top ?? 0

    readonly property var bar: BarGlassService.barFor(screen)
    readonly property bool integrated: active && bar !== null
        && OverlayService.topMargin(screen) > 0
    readonly property Item renderParent: integrated ? bar.glassHost : standaloneParent

    property bool backgroundLoadersReady: false

    function syncBackgroundLoaders(): void {
        if (!backgroundLoadersReady)
            return;
        const integratedParent = bar?.glassHost ?? null;
        if (integratedLoader.parent !== integratedParent) {
            integratedLoader.active = false;
            integratedLoader.parent = integratedParent;
        }
        if (standaloneLoader.parent !== standaloneParent) {
            standaloneLoader.active = false;
            standaloneLoader.parent = standaloneParent;
        }
        integratedLoader.active = active && integrated && integratedParent !== null;
        standaloneLoader.active = active && !integrated && standaloneParent !== null;
    }

    onActiveChanged: syncBackgroundLoaders()
    onIntegratedChanged: syncBackgroundLoaders()
    onBarChanged: syncBackgroundLoaders()
    onStandaloneParentChanged: syncBackgroundLoaders()
    Component.onCompleted: {
        backgroundLoadersReady = true;
        syncBackgroundLoaders();
        BarGlassService.registerBackground(root);
    }
    Component.onDestruction: BarGlassService.unregisterBackground(root)

    // A layered item keeps resources tied to its native window. Create each
    // background in its final window instead of reparenting an existing layer
    // when a popup closes or its output enters fullscreen.
    Loader {
        id: integratedLoader
        parent: null
        active: false
        sourceComponent: backgroundComponent
        x: root.x + root.globalX
        y: root.y + root.globalY - Theme.barHeight
        width: root.width
        height: root.height
        visible: root.visible
        opacity: root.opacity
        enabled: false
        z: root.z
        rotation: root.rotation
        scale: root.scale
        transformOrigin: root.transformOrigin
    }

    Loader {
        id: standaloneLoader
        parent: null
        active: false
        sourceComponent: backgroundComponent
        x: root.x
        y: root.y
        width: root.width
        height: root.height
        visible: root.visible
        opacity: root.opacity
        enabled: false
        z: root.z
        rotation: root.rotation
        scale: root.scale
        transformOrigin: root.transformOrigin
    }

    Component {
        id: backgroundComponent

        AttachedPanel {
            anchors.fill: parent
            color: root.backgroundContent !== null ? "transparent" : root.color
            borderColor: root.borderColor
            cornerRadius: root.cornerRadius
            attachRightEdge: root.attachRightEdge
            borderWidth: root.borderWidth
            edgeSoftness: root.edgeSoftness
            flowProgress: root.flowProgress
            flowStrength: root.flowStrength
            flowAnchor: root.flowAnchor
            joinProgress: root.joinProgress
            revealProgress: root.revealProgress

            Loader {
                anchors.fill: parent
                active: root.backgroundContent !== null
                sourceComponent: root.backgroundContent
            }
        }
    }
}
