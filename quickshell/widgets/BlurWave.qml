import QtQuick
import "../components"

// Paint a soft wave of glass on a native surface with compositor blur enabled.
// The dialog belongs to a separate surface above this one and stays sharp.
ShaderEffect {
    id: effect

    property real progress: 0
    property color color: Theme.barBackground
    property vector4d dialogBounds: Qt.vector4d(width / 2, height / 2, 0, 0)
    property real dialogRadius: 0
    property real feather: 160
    property real joinHeight: 0
    property bool compensateBackground: false
    readonly property real backgroundPass: compensateBackground ? 1 : 0
    readonly property real waveOpacity: Math.min(1, progress / 0.01)
    readonly property vector2d effectSize: Qt.vector2d(width, height)
    readonly property real maximumSpread: {
        const halfWidth = dialogBounds.z / 2;
        const halfHeight = dialogBounds.w / 2;
        const centerX = dialogBounds.x + halfWidth;
        const centerY = dialogBounds.y + halfHeight;
        const radius = Math.max(0, Math.min(dialogRadius, halfWidth, halfHeight));
        const dx = Math.max(centerX, width - centerX) - halfWidth + radius;
        const dy = Math.max(centerY, height - centerY) - halfHeight + radius;
        return Math.max(0, Math.hypot(Math.max(dx, 0), Math.max(dy, 0))
            + Math.min(Math.max(dx, dy), 0) - radius);
    }
    // Grow outward from every edge of the dialog, then retrace its outline
    // on dismissal. The feather also reaches the farthest panel corner.
    readonly property real waveSpread: progress * (maximumSpread + feather / 2)
    fragmentShader: Qt.resolvedUrl("../assets/shaders/glass-connected-wave.frag.qsb")
}
