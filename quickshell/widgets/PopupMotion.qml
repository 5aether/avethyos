import QtQuick

// Keep window lifetime separate from the requested state so closing can finish.
// Attached cards scroll out of their surface; floating cards expand from a bubble.
Item {
    id: motion
    visible: false

    property bool opened: false
    property bool attached: true
    property bool animationsEnabled: true
    property bool scaleOnOpen: true
    property real distance: 24
    property real horizontalDistance: 0
    property real wobbleStrength: 0.12
    property int openDuration: 320
    property int settleDuration: 120
    property int closeDuration: 220
    property real progress: 0
    property real settle: 1
    property bool initialized: false
    readonly property bool active: opened || progress > 0 || entrance.running || exitMotion.running
    readonly property real wobble: wobbleStrength * Math.sin(settle * Math.PI)
        * Math.pow(1 - settle, 2)
    readonly property real flow: Math.sin(progress * Math.PI) * (1 - progress)
    readonly property real offsetX: horizontalDistance * (1 - progress)
    readonly property real offsetY: (attached ? -1 : 1) * distance * (1 - progress)
    readonly property real scaleX: (scaleOnOpen ? (attached ? 1 - 0.055 * flow : progress) : 1)
        * (1 - 0.012 * wobble)
    readonly property real scaleY: (scaleOnOpen ? (attached ? 1 + 0.018 * flow : progress * (1 + 0.035 * flow)) : 1)
        * (1 + 0.022 * wobble)

    signal closed()
    signal settled()

    function sync() {
        entrance.stop();
        exitMotion.stop();
        settle = 1;
        if (!animationsEnabled) {
            progress = opened ? 1 : 0;
            if (!opened)
                closed();
            return;
        }
        if (opened) {
            entrance.start();
        } else if (progress > 0) {
            exitMotion.start();
        } else {
            closed();
        }
    }

    onOpenedChanged: if (initialized) sync()
    onAnimationsEnabledChanged: if (initialized) sync()
    Component.onCompleted: {
        initialized = true;
        sync();
    }

    SequentialAnimation {
        id: entrance
        NumberAnimation {
            target: motion
            property: "progress"
            to: 1
            duration: motion.openDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.22, 0.75, 0.25, 1, 1, 1]
        }
        NumberAnimation {
            target: motion
            property: "settle"
            from: 0
            to: 1
            duration: motion.settleDuration
            easing.type: Easing.Linear
        }
        onFinished: motion.settled()
    }

    NumberAnimation {
        id: exitMotion
        target: motion
        property: "progress"
        to: 0
        duration: motion.closeDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.55, 0, 0.8, 0.45, 1, 1]
        onFinished: motion.closed()
    }
}
