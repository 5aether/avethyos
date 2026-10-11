import QtQuick
import "../components"

// A panel joined to the bar, optionally also to the right screen edge.
// Centered panels have matching shoulders and rounded lower corners.
Item {
    id: panel

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
    property real contentOpacity: 1
    // Grow the connecting curves before extending the body. The layout and
    // texture stay full size so controls never stretch during the reveal.
    readonly property real revealedHeight: Math.min(height, 3 * cornerRadius) * joinProgress
        + Math.max(0, height - 3 * cornerRadius) * revealProgress
    readonly property real revealedRadius: Math.min(cornerRadius * joinProgress,
        revealedHeight / 3)
    readonly property real bodyLeft: cornerRadius
    readonly property real bodyBottom: height - cornerRadius

    layer.enabled: true
    layer.smooth: true
    layer.effect: ShaderEffect {
        property var source
        property vector2d flowSize: Qt.vector2d(panel.width, panel.height)
        property vector2d flowAnchor: panel.flowAnchor
        property real flowProgress: panel.flowProgress
        property real flowStrength: panel.flowStrength
        property vector2d panelSize: Qt.vector2d(panel.width, panel.height)
        property real cornerRadius: panel.revealedRadius
        property real revealHeight: panel.revealedHeight
        property real contentOpacity: panel.contentOpacity
        property real borderWidth: panel.borderWidth
        property real attachRightEdge: panel.attachRightEdge ? 1 : 0
        property real edgeSoftness: panel.edgeSoftness
        property color borderColor: panel.borderColor
        mesh: Qt.size(18, 22)
        vertexShader: Qt.resolvedUrl("../assets/shaders/popup-flow.vert.qsb")
        fragmentShader: Qt.resolvedUrl("../assets/shaders/attached-panel.frag.qsb")
    }

    Rectangle {
        anchors.fill: parent
        color: panel.color
    }
}
