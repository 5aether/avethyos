import QtQuick
import QtMultimedia as Multimedia
import Quickshell
import Quickshell.Wayland
import "../components"

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window
        required property var modelData

        screen: modelData
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        aboveWindows: false
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        color: Theme.colors.base

        // Maps the shared fill mode onto the QtMultimedia video output.
        function outputFillMode() {
            return WallpaperManager.fillMode === Image.PreserveAspectFit
                 ? Multimedia.VideoOutput.PreserveAspectFit
                 : WallpaperManager.fillMode === Image.Stretch
                   ? Multimedia.VideoOutput.Stretch
                   : Multimedia.VideoOutput.PreserveAspectCrop;
        }

        // Wallpapers are decorative: the track is muted and silent so it never
        // takes the default audio sink away from the user's real output.
        Multimedia.AudioOutput {
            id: silentAudio
            muted: true
            volume: 0
        }

        // Starts or stops playback so it always matches shouldRun, whatever
        // changed: the toggle, the picked path, or the initial binding.
        function syncPlayback() {
            if (WallpaperManager.shouldRun)
                player.play();
            else
                player.stop();
        }

        Multimedia.MediaPlayer {
            id: player
            source: WallpaperManager.shouldRun ? WallpaperManager.requestedPath : ""
            videoOutput: video
            audioOutput: silentAudio
            loops: Multimedia.MediaPlayer.Infinite
            autoPlay: false

            onErrorOccurred: (error, errorString) => {
                if (error !== Multimedia.MediaPlayer.NoError)
                    WallpaperManager.reportError(errorString);
            }

            // Clearing an error as soon as playback actually starts means a
            // stale message never survives a successful retry.
            onPlaybackStateChanged: {
                if (playbackState === Multimedia.MediaPlayer.PlayingState)
                    WallpaperManager.error = "";
            }

            // The new source is only ready to play once the assignment has
            // settled, so defer the start by one event-loop turn.
            onSourceChanged: Qt.callLater(() => window.syncPlayback())

            Component.onCompleted: window.syncPlayback()
        }

        Multimedia.VideoOutput {
            id: video
            anchors.fill: parent
            fillMode: window.outputFillMode()
            orientation: 0
        }

        Connections {
            target: WallpaperManager
            function onShouldRunChanged() { window.syncPlayback(); }
        }
    }
}
