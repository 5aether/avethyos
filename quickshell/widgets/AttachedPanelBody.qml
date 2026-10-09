import QtQuick
import "../components"

// An opaque body below the shared glass join keeps compositor blur away from
// the panel's antialiased lower edge, where it would expose a bright fringe.
Rectangle {
    id: body

    property real blendHeight: 36
    color: Theme.colors.mantle
    layer.enabled: true
    layer.smooth: true
    layer.effect: ShaderEffect {
        property var source
        property real blendFraction: Math.min(1, body.blendHeight / Math.max(1, body.height))
        fragmentShader: Qt.resolvedUrl("../assets/shaders/cover-blend.frag.qsb")
    }
}
