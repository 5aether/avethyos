import QtQuick

// Keep window lifetime separate from the requested state so closing can finish.
// Attached surfaces grow from the bar before their controls appear. Floating
// cards and individual rows retain their translation and bubble motion.
Item {
    id: motion
    visible: false

    property bool opened: false
    // Heavy popups can follow their rendered frames so window setup and a
    // blocked render never consume the entire reveal before it is painted.
    property var frameSource: null
    property bool frameDriven: frameSource !== null
    property double lastFrameTime: -1
    property bool attached: true
    property bool animationsEnabled: true
    property bool scaleOnOpen: true
    property bool expandFromBar: attached && scaleOnOpen
    property real distance: 24
    property real horizontalDistance: 0
    property real wobbleStrength: 0.12
    property int openDuration: expandFromBar ? 380 : 320
    property int settleDuration: 120
    property int closeDuration: expandFromBar ? 260 : 220
    property real progress: 0
    property real settle: 1
    property bool initialized: false
    property int entranceDuration: openDuration
    property int exitDuration: closeDuration
    readonly property bool active: opened || progress > 0 || entrance.running || exitMotion.running
    readonly property real joinProgress: expandFromBar ? smoothPhase(0, 0.20) : 1
    readonly property real expansionProgress: {
        if (!expandFromBar)
            return 1;
        const body = smoothPhase(0.20, 1);
        return body * 0.65 + (1 - Math.pow(1 - body, 3)) * 0.35;
    }
    readonly property real contentOpacity: expandFromBar ? smoothPhase(0.26, 0.62) : 1
    readonly property real wobble: expandFromBar ? 0 : wobbleStrength * Math.sin(settle * Math.PI)
        * Math.pow(1 - settle, 2)
    readonly property real flow: Math.sin(progress * Math.PI) * (1 - progress)
    readonly property real offsetX: expandFromBar ? 0 : horizontalDistance * (1 - progress)
    readonly property real offsetY: expandFromBar ? 0 : (attached ? -1 : 1) * distance * (1 - progress)
    readonly property real scaleX: expandFromBar ? 1 : (scaleOnOpen ? (attached ? 1 - 0.055 * flow : progress) : 1)
        * (1 - 0.012 * wobble)
    readonly property real scaleY: expandFromBar ? 1 : (scaleOnOpen ? (attached ? 1 + 0.018 * flow : progress * (1 + 0.035 * flow)) : 1)
        * (1 + 0.022 * wobble)

    signal closed()
    signal settled()

    function smoothPhase(start: real, end: real): real {
        const value = Math.max(0, Math.min(1, (progress - start) / (end - start)));
        return value * value * (3 - 2 * value);
    }

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
        if (frameDriven) {
            lastFrameTime = -1;
            if (opened || progress > 0)
                frameSource?.update();
            else
                closed();
            return;
        }
        if (opened) {
            entranceDuration = Math.max(1, Math.round(openDuration * (1 - progress)));
            entrance.start();
        } else if (progress > 0) {
            exitDuration = Math.max(1, Math.round(closeDuration * progress));
            exitMotion.start();
        } else {
            closed();
        }
    }

    function advanceFrame(timestamp: real): void {
        if (!initialized || !animationsEnabled || !frameDriven || !frameSource
            || (opened ? progress >= 1 : progress <= 0))
            return;
        // Preserve intermediate frames even after a slow map or buffer
        // allocation. The first frame paints the current starting position.
        const elapsed = lastFrameTime >= 0 ? Math.max(0, Math.min(32, timestamp - lastFrameTime)) : 0;
        lastFrameTime = timestamp;
        if (opened) {
            progress = Math.min(1, progress + elapsed / Math.max(1, openDuration));
            if (progress === 1) {
                settled();
                return;
            }
        } else {
            progress = Math.max(0, progress - elapsed / Math.max(1, closeDuration));
            if (progress === 0) {
                closed();
                return;
            }
        }
        frameSource.update();
    }

    Connections {
        target: motion.frameSource
        function onFrameSwapped() { motion.advanceFrame(Date.now()); }
    }

    onOpenedChanged: if (initialized) sync()
    onFrameDrivenChanged: if (initialized) sync()
    onFrameSourceChanged: if (initialized) sync()
    onAnimationsEnabledChanged: if (initialized) sync()
    onExpandFromBarChanged: if (initialized) sync()
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
            duration: motion.entranceDuration
            easing.type: motion.expandFromBar ? Easing.Linear : Easing.BezierSpline
            // Setting bezierCurve also sets its type in Qt. Linear control
            // points keep the attached timeline linear in either update order.
            easing.bezierCurve: motion.expandFromBar ? [0, 0, 1, 1, 1, 1]
                : [0.22, 0.75, 0.25, 1, 1, 1]
        }
        NumberAnimation {
            target: motion
            property: "settle"
            from: 0
            to: 1
            duration: motion.expandFromBar ? 0 : motion.settleDuration
            easing.type: Easing.Linear
        }
        onFinished: motion.settled()
    }

    NumberAnimation {
        id: exitMotion
        target: motion
        property: "progress"
        to: 0
        duration: motion.exitDuration
        easing.type: motion.expandFromBar ? Easing.Linear : Easing.BezierSpline
        easing.bezierCurve: motion.expandFromBar ? [0, 0, 1, 1, 1, 1]
            : [0.55, 0, 0.8, 0.45, 1, 1]
        onFinished: motion.closed()
    }
}
