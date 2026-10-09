pragma Singleton
import QtQuick 2.15
QtObject {
    readonly property SystemPalette active: SystemPalette { colorGroup: SystemPalette.Active }
    readonly property SystemPalette disabled: SystemPalette { colorGroup: SystemPalette.Disabled }
    readonly property color primary: active.highlight
    readonly property color primaryText: active.highlightedText
    readonly property color text: active.windowText
    readonly property color muted: Qt.rgba(text.r, text.g, text.b, 0.65)
    readonly property color window: active.window
    readonly property color base: active.base
    readonly property color button: active.button
    readonly property color hover: active.light
    readonly property color border: Qt.rgba(active.mid.r, active.mid.g, active.mid.b, 0.24)
    readonly property bool dark: (window.r + window.g + window.b) < 1.5
    readonly property color glass: Qt.rgba(window.r, window.g, window.b, dark ? 0.88 : 0.94)
    readonly property color floating: Qt.rgba(button.r, button.g, button.b, dark ? 0.94 : 0.97)
    readonly property color hoverOverlay: Qt.rgba(text.r, text.g, text.b, 0.08)
    readonly property color menuMuted: Qt.rgba(text.r * 0.55 + button.r * 0.45,
                                              text.g * 0.55 + button.g * 0.45,
                                              text.b * 0.55 + button.b * 0.45, 1)
}
