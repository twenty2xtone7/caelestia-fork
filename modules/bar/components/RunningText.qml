pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import Quickshell
import Quickshell.Services.Mpris
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property var bar

    // Find the player currently playing with an active title, or fallback to first/active player
    readonly property MprisPlayer player: {
        const playing = Players.list.find(p => p.playbackStatus === MprisPlaybackState.Playing && (p.trackTitle ?? "") !== "");
        return playing ?? Players.active ?? (Players.list.length > 0 ? Players.list[0] : null);
    }

    // Feed global Lyrics singleton with the resolved player's metadata
    readonly property var activeTrack: player ? {
        "artist": player.trackArtist ?? "",
        "title": player.trackTitle ?? "",
        "album": player.trackAlbum ?? "",
        "length": player.length ?? 0
    } : null

    onActiveTrackChanged: {
        if (activeTrack && activeTrack.title !== "") {
            Lyrics.setTrack(activeTrack.artist, activeTrack.title, activeTrack.album, activeTrack.length);
            console.log(`[Diagnostic] setTrack: "${activeTrack.title}" by "${activeTrack.artist}", hasLyrics=${Lyrics.hasLyrics}, loading=${Lyrics.loading}`);
        } else {
            Lyrics.clearTrack();
            console.log("[Diagnostic] clearTrack called");
        }
    }

    Connections {
        target: Lyrics
        function onHasLyricsChanged(): void {
            console.log(`[Diagnostic] Lyrics.hasLyricsChanged: ${Lyrics.hasLyrics}, count=${Lyrics.lyrics.length}`);
        }
        function onLyricsChanged(): void {
            console.log(`[Diagnostic] Lyrics.lyricsChanged: count=${Lyrics.lyrics.length}`);
        }
        function onLoadingChanged(): void {
            console.log(`[Diagnostic] Lyrics.loadingChanged: ${Lyrics.loading}`);
        }
    }

    Connections {
        target: root.player
        function onPlaybackStatusChanged(): void {
            console.log(`[Diagnostic] player playbackStatus changed: ${root.player?.playbackStatus}`);
        }
    }
    readonly property var playerPlaybackState: player?.playbackState
    onPlayerPlaybackStateChanged: console.log(`[Diagnostic] playbackState=${playerPlaybackState}`)

    readonly property bool isPlaying: root.player?.playbackStatus === MprisPlaybackState.Playing

    onIsPlayingChanged: console.log(`[Diagnostic] isPlaying=${isPlaying}, player=${root.player?.identity}, playbackStatus=${root.player?.playbackStatus}`)
    readonly property real position: root.player?.position ?? 0

    // Force position updates every 50ms during playback
    Timer {
        running: root.isPlaying && Lyrics.hasLyrics
        interval: 50
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    readonly property int currentIndex: Lyrics.hasLyrics ? Lyrics.indexForTime(root.position) : -1
    readonly property string currentLyric: (currentIndex >= 0 && currentIndex < Lyrics.lyrics.length) ? Lyrics.lyrics[currentIndex].trim() : ""
    readonly property bool showLyrics: Lyrics.hasLyrics && root.isPlaying && currentLyric !== ""

    onShowLyricsChanged: console.log(`[Diagnostic] showLyrics=${showLyrics}, hasLyrics=${Lyrics.hasLyrics}, isPlaying=${isPlaying}, lyric="${currentLyric}", count=${Lyrics.lyrics.length}`)

    onShowLyricsChanged: console.log(`[Diagnostic] showLyrics=${showLyrics}, hasLyrics=${Lyrics.hasLyrics}, isPlaying=${isPlaying}, lyric="${currentLyric}", player=${root.player?.identity}`)
    onCurrentLyricChanged: console.log(`[Diagnostic] currentLyric changed: "${currentLyric}"`)

    // Fallback window title
    readonly property string windowTitle: {
        const title = Hypr.activeToplevel?.title;
        if (!title) return Tr.trCtx("Desktop", "shown when no window is focused");
        if (Config.bar.activeWindow.compact) {
            const parts = title.split(/\s+[\-\u2013\u2014]\s+/);
            if (parts.length > 1) return parts[parts.length - 1].trim();
        }
        return title;
    }

    clip: true
    implicitWidth: bar.horizontal 
        ? (icon.implicitWidth + Tokens.spacing.small + (showLyrics ? lyricsViewport.implicitWidth : titleText.implicitWidth))
        : Math.max(icon.implicitWidth, titleText.implicitHeight)
    implicitHeight: bar.horizontal 
        ? Math.max(icon.implicitHeight, titleText.implicitHeight) 
        : (icon.implicitHeight + Tokens.spacing.small + titleText.implicitWidth)

    onImplicitWidthChanged: console.log(`[Diagnostic] implicitWidth=${implicitWidth}, bar.width=${bar.width}, visible=${visible}`)

    // App icon
    MaterialIcon {
        id: icon
        x: root.bar.horizontal ? 0 : (parent.width - width) / 2
        y: root.bar.horizontal ? (parent.height - height) / 2 : 0
        animate: true
        text: root.showLyrics ? "music_note" : Icons.getAppCategoryIcon(Hypr.activeToplevel?.lastIpcObject.class, "desktop_windows")
        color: Colours.palette.m3primary
    }

    // Container for text
    Item {
        id: container
        x: root.bar.horizontal ? icon.width + Tokens.spacing.small : 0
        width: root.width - x
        height: root.height
        clip: true

        // Window title fallback
        StyledText {
            id: titleText
            anchors.verticalCenter: parent.verticalCenter
            text: root.windowTitle
            font: Tokens.font.body.builders.small.letterSpacing(1.2).build()
            color: Colours.palette.m3onSurface
            elide: Text.ElideRight
            width: root.showLyrics ? 0 : Math.max(implicitWidth, 200)
            opacity: root.showLyrics ? 0 : 1
            Behavior on opacity { Anim { type: Anim.DefaultEffects } }
        }

        // Scrolling lyrics viewport
        Item {
            id: lyricsViewport
            anchors.fill: parent
            opacity: root.showLyrics ? 1 : 0
            visible: opacity > 0
            implicitWidth: Math.min(350, Math.max(150, root.bar.width * 0.4))

            Behavior on opacity { Anim { type: Anim.DefaultEffects } }

            // Calculate progress through current lyric line
            readonly property real startTime: Lyrics.timeForIndex(root.currentIndex)
            readonly property real endTime: Lyrics.timeForIndex(root.currentIndex + 1)
            readonly property real duration: (endTime > startTime) ? (endTime - startTime) : 3.0
            readonly property real elapsed: root.position - startTime
            readonly property real progress: Math.max(0, Math.min(1, duration > 0 ? (elapsed / duration) : 0))

            StyledText {
                id: lyricText
                text: root.currentLyric
                font: Tokens.font.body.builders.small.letterSpacing(1.2).build()
                color: Colours.palette.m3primary
                anchors.verticalCenter: parent.verticalCenter
                // Smooth continuous scroll from right to left based on playback progress
                x: parent.width - (parent.width + implicitWidth) * lyricsViewport.progress
            }

            // Horizontal fade masks at both edges
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: Rectangle {
                    width: lyricsViewport.width
                    height: lyricsViewport.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.15; color: "white" }
                        GradientStop { position: 0.85; color: "white" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
            }
        }
    }

    Behavior on implicitWidth { Anim {} }
    Behavior on implicitHeight { Anim {} }
}
