import QtQuick
import QtQuick.Effects
import "../components"

// Decode small cover textures and crossfade complete, already blurred frames.
// The previous frame remains intact while a new URL is loading.
Item {
    id: root
    property string artUrl: ""
    property real blendHeight: 36
    property bool secondActive: false
    property real blend: 0
    property bool ready: false

    layer.enabled: true
    layer.smooth: true
    layer.effect: ShaderEffect {
        property var source
        property real blendFraction: Math.min(1, root.blendHeight / Math.max(1, root.height))
        fragmentShader: Qt.resolvedUrl("../assets/shaders/cover-blend.frag.qsb")
    }

    function prepare() {
        if (crossfade.running)
            return;
        const next = root.secondActive ? first : second;
        if (!artUrl.length) {
            next.url = "";
            commit(next);
        } else if (next.url === artUrl && next.loaded) {
            commit(next);
        } else {
            next.url = artUrl;
        }
    }

    function commit(frame) {
        if (crossfade.running || frame === (secondActive ? second : first))
            return;
        secondActive = frame === second;
        crossfade.to = secondActive ? 1 : 0;
        ready = true;
        crossfade.start();
    }

    onArtUrlChanged: prepare()
    Component.onCompleted: prepare()

    component BackdropFrame: Item {
        id: frame
        property string url: ""
        readonly property bool loaded: cover.status === Image.Ready
        clip: true

        // This fallback also covers loading errors without flashing to black.
        Rectangle { anchors.fill: parent; color: Theme.colors.surface0 }
        Image {
            id: cover
            visible: false
            x: -32
            y: -32
            width: frame.width + 64
            height: frame.height + 64
            source: frame.url
            sourceSize.width: 128
            sourceSize.height: 128
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            onStatusChanged: {
                if (status === Image.Ready || status === Image.Error)
                    root.commit(frame);
            }
        }
        MultiEffect {
            x: -32
            y: -32
            width: frame.width + 64
            height: frame.height + 64
            source: cover
            visible: cover.status === Image.Ready
            blurEnabled: true
            blurMax: 32
            blur: 1
            autoPaddingEnabled: false
        }
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.025, 0.02, 0.035, 0.72)
        }
    }

    BackdropFrame { id: first; anchors.fill: parent }
    BackdropFrame { id: second; anchors.fill: parent; opacity: root.blend }
    NumberAnimation {
        id: crossfade
        target: root
        property: "blend"
        duration: 180
        easing.type: Easing.OutCubic
        onFinished: {
            const current = root.secondActive ? second : first;
            if (current.url !== root.artUrl)
                root.prepare();
        }
    }
}
