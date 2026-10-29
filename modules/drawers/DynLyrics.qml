pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services

// Dyn-Lyrics: Dynamic Island-style panel anchored to top edge.
// Reuses the animation/geometry behavior from Caelestia's bar popouts.
Item {
    id: root
    objectName: "dynLyrics"

    required property ShellScreen screen
    property bool active: false

    readonly property bool isPlaying: Players.active?.isPlaying ?? false
    readonly property real position: Players.active?.position ?? 0

    readonly property int currentIndex: Lyrics.hasLyrics ? Lyrics.indexForTime(root.position) : -1
    readonly property string currentLine: (currentIndex >= 0 && currentIndex < Lyrics.lyrics.length) ? Lyrics.lyrics[currentIndex].trim() : ""

    // Geometry & Animation
    readonly property real pillHeight: 40
    readonly property real pillWidth: Math.min(800, screen.width * 0.8)
    
    y: (active ? 10 : -pillHeight - 10)
    opacity: active ? 1 : 0
    
    Behavior on y { Anim { type: Anim.DefaultSpatial } }
    Behavior on opacity { Anim { type: Anim.DefaultEffects } }

    anchors.horizontalCenter: parent.horizontalCenter
    width: pillWidth
    height: pillHeight
    
    z: 1000 // Ensure it's above other windows

    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.95)
        radius: height / 2
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: Tokens.spacing.medium
            width: parent.width - 40

            MaterialIcon {
                text: "music_note"
                color: Colours.palette.m3primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Marquee {
                id: marquee
                text: root.currentLine || (Lyrics.loading ? "Loading lyrics..." : "No lyrics available")
                color: Colours.palette.m3onSurface
                width: parent.width - 40
                height: parent.height
                running: root.isPlaying && root.active
            }
        }

        StateLayer {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: root.active = false
        }
    }

    // Coordinated state management
    onActiveChanged: {
        if (active) {
            const p = Players.active;
            if (p) Lyrics.setTrack(p.trackArtist, p.trackTitle, p.trackAlbum, p.length);
        }
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "dynLyrics"
        component: root
    }
}
