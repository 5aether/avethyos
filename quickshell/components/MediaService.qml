pragma Singleton

import QtQuick
import Quickshell.Services.Mpris

// MPRIS is reactive over D-Bus, replacing repeated playerctl processes.
QtObject {
    id: root

    readonly property var players: Mpris.players.values
    property var player: null
    property var selectedPlayer: null

    function containsPlayer(candidate) {
        if (!candidate)
            return false;
        for (let i = 0; i < players.length; ++i) {
            if (players[i] === candidate)
                return true;
        }
        return false;
    }

    function playerName(candidate) {
        if (!candidate)
            return "Unknown player";
        if ((candidate.identity ?? "").length > 0)
            return candidate.identity;
        if ((candidate.desktopEntry ?? "").length > 0)
            return candidate.desktopEntry;
        const address = candidate.dbusName ?? "";
        const prefix = "org.mpris.MediaPlayer2.";
        return address.startsWith(prefix) ? address.slice(prefix.length) : address;
    }

    function selectPlayer(candidate) {
        if (containsPlayer(candidate))
            selectedPlayer = candidate;
    }

    function selectCurrentPlayer() {
        if (player)
            selectedPlayer = player;
    }

    function updatePlayer() {
        let newPlayer = null;

        // Preserve the current source while it is still playing. If another
        // source starts later, its playback-state connection below promotes it
        // immediately, making the bar follow the most recent active source.
        if (containsPlayer(player) && player.isPlaying) {
            newPlayer = player;
        } else {
            for (let i = 0; i < players.length; ++i) {
                if (players[i] && players[i].isPlaying) {
                    newPlayer = players[i];
                    break;
                }
            }
        }

        // With nothing playing, retain the last source if it still exists so
        // paused track metadata remains visible in the bar.
        if (!newPlayer && containsPlayer(player))
            newPlayer = player;
        if (!newPlayer && players.length > 0)
            newPlayer = players[0];

        player = newPlayer;

        if (!containsPlayer(selectedPlayer))
            selectedPlayer = newPlayer;
    }

    onPlayersChanged: updatePlayer()

    Component.onCompleted: updatePlayer()

    property Instantiator playerConnections: Instantiator {
        model: root.players
        delegate: Connections {
            required property var modelData
            target: modelData

            function onPlaybackStateChanged() {
                if (modelData.isPlaying)
                    root.player = modelData;
                else
                    root.updatePlayer();
            }
        }
    }

    property Timer updateTimer: Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.updatePlayer()
    }
}
