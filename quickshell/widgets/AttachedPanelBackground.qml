import QtQuick
import "../components"

// Draw the attached outline and optional glass-to-body blend directly. Unlike
// AttachedPanel, this does not render its children into an offscreen texture.
ShaderEffect {
    property color color: Theme.colors.mantle
    property real cornerRadius: 20
    property real edgeSoftness: 2
    property real blendHeight: 0
    property real flowProgress: 1
    property real flowStrength: 0
    property vector2d flowAnchor: Qt.vector2d(1, 0)
    readonly property vector2d flowSize: Qt.vector2d(width, height)
    // A short backdrop can draw only the top strip of a taller panel.
    property real panelHeight: height
    readonly property vector2d panelSize: Qt.vector2d(width, panelHeight)
    readonly property vector2d drawSize: Qt.vector2d(width, height)

    mesh: Qt.size(18, 22)
    vertexShader: Qt.resolvedUrl("../assets/shaders/popup-flow.vert.qsb")
    fragmentShader: Qt.resolvedUrl("../assets/shaders/attached-panel-background.frag.qsb")
}
