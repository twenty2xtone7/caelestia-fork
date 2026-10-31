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
    required property Brightness.Monitor monitor
    property color colour: Colours.palette.m3primary

    readonly property bool horizontal: BarState.horizontal

    // 1. Resolve player: First look for a playing player with a valid track, fallback to Players.active
    readonly property MprisPlayer player: {
        const playing = Players.list.find(p => p.isPlaying && (p.trackTitle ?? "") !== "");
        return playing ?? Players.active ?? (Players.list.length > 0 ? Players.list[0] : null);
    }

    // Lyrics are fed by services/Players.qml; this only consumes them.
    readonly property bool isPlaying: root.player?.isPlaying ?? false
    readonly property real position: root.player?.position ?? 0

    // Force position updates every 50ms during playback to keep lyrics in sync
    Timer {
        running: root.isPlaying && Lyrics.hasLyrics
        interval: 50
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    // Read position into a local first: with the call inline inside the
    // ternary QML does not register `root.position` as a binding dependency,
    // so the index freezes at -1 and lyrics never appear.
    readonly property int currentIndex: {
        const pos = root.position;
        return Lyrics.hasLyrics ? Lyrics.indexForTime(pos) : -1;
    }
    readonly property string currentLyric: (currentIndex >= 0 && currentIndex < Lyrics.lyrics.length) ? Lyrics.lyrics[currentIndex].trim() : ""
    
    // Only show lyrics when horizontal, has lyrics, and actively playing with a line
    readonly property bool showLyrics: root.horizontal && Lyrics.hasLyrics && root.isPlaying && currentLyric !== ""

    readonly property string windowTitle: {
        const title = Hypr.activeToplevel?.title;
        if (!title)
            return Tr.trCtx("Desktop", "shown when no window is focused");
        if (Config.bar.activeWindow.compact) {
            const parts = title.split(/\s+[\-\u2013\u2014]\s+/);
            if (parts.length > 1)
                return parts[parts.length - 1].trim();
        }
        return title;
    }

    // Length available along the bar's main axis, after every other entry.
    readonly property int maxLength: {
        const otherModules = bar.children.filter(c => c.entryId && c.item !== this && c.entryId !== "spacer");
        const otherLength = otherModules.reduce((acc, curr) => acc + (horizontal ? curr.width : (curr.item.nonAnimHeight ?? curr.height)), 0);
        return (horizontal ? bar.width : bar.height) - otherLength - bar.spacing * (bar.children.length - 1) - bar.vPadding * 2;
    }

    property Title current: text1

    clip: true
    implicitWidth: horizontal 
        ? (icon.implicitWidth + Tokens.spacing.small + (showLyrics ? lyricsViewport.implicitWidth : current.implicitWidth)) 
        : Math.max(icon.implicitWidth, current.implicitHeight)
    implicitHeight: horizontal 
        ? Math.max(icon.implicitHeight, current.implicitHeight) 
        : (icon.implicitHeight + Tokens.spacing.small + current.implicitWidth)

    Loader {
        asynchronous: true
        anchors.fill: parent
        active: !Config.bar.activeWindow.showOnHover

        sourceComponent: MouseArea {
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onPositionChanged: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent && popouts.currentName !== "activewindow")
                    popouts.hasCurrent = false;
            }
            onClicked: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent) {
                    popouts.hasCurrent = false;
                } else {
                    popouts.currentName = "activewindow";
                    popouts.currentCenter = root.horizontal ? root.mapToItem(root.bar, root.implicitWidth / 2, 0).x : root.mapToItem(root.bar, 0, root.implicitHeight / 2).y;
                    popouts.hasCurrent = true;
                }
            }
        }
    }

    MaterialIcon {
        id: icon

        x: root.horizontal ? 0 : (parent.width - width) / 2
        y: root.horizontal ? (parent.height - height) / 2 : 0

        animate: true
        text: root.showLyrics ? "music_note" : Icons.getAppCategoryIcon(Hypr.activeToplevel?.lastIpcObject.class, "desktop_windows")
        color: root.colour
    }

    // Normal Active Window Titles with cross-fade
    Title {
        id: text1
        opacity: root.showLyrics ? 0 : (root.current === this ? 1 : 0)
    }

    Title {
        id: text2
        opacity: root.showLyrics ? 0 : (root.current === this ? 1 : 0)
    }

    TextMetrics {
        id: metrics

        text: root.windowTitle
        font: root.Tokens.font.body.builders.small.letterSpacing(1.4).build()
        elide: Qt.ElideRight
        elideWidth: root.maxLength - (root.horizontal ? icon.width : icon.height)

        onTextChanged: {
            const next = root.current === text1 ? text2 : text1;
            next.text = elidedText;
            root.current = next;
        }
        onElideWidthChanged: root.current.text = elidedText
    }

    // Horizontal Scrolling Lyrics Viewport
    Item {
        id: lyricsViewport
        visible: root.showLyrics
        opacity: root.showLyrics ? 1 : 0
        x: icon.width + Tokens.spacing.small
        y: (root.height - height) / 2
        implicitWidth: Math.min(350, Math.max(150, root.maxLength - icon.width - Tokens.spacing.small))
        height: root.height
        clip: true

        Behavior on opacity {
            Anim { type: Anim.DefaultEffects }
        }

        readonly property real startTime: Lyrics.timeForIndex(root.currentIndex)
        readonly property real endTime: Lyrics.timeForIndex(root.currentIndex + 1)
        readonly property real duration: (endTime > startTime) ? (endTime - startTime) : 3.0
        readonly property real elapsed: root.position - startTime
        readonly property real progress: Math.max(0, Math.min(1, duration > 0 ? (elapsed / duration) : 0))

        StyledText {
            id: lyricText
            text: root.currentLyric
            font: root.Tokens.font.body.builders.small.letterSpacing(1.4).build()
            color: root.colour
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width - (parent.width + implicitWidth) * lyricsViewport.progress
        }

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

    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on implicitHeight {
        Anim {}
    }

    component Title: StyledText {
        id: text

        x: root.horizontal ? icon.width + Tokens.spacing.small : (root.width - width) / 2
        y: root.horizontal ? (root.height - height) / 2 : icon.height + Tokens.spacing.small

        font: metrics.font
        color: root.colour
        opacity: root.current === this ? 1 : 0
        horizontalAlignment: Text.AlignLeft

        transform: [
            Translate {
                x: (root.horizontal || !root.Config.bar.activeWindow.inverted) ? 0 : -text.implicitWidth + text.implicitHeight
            },
            Rotation {
                angle: root.horizontal ? 0 : (root.Config.bar.activeWindow.inverted ? 270 : 90)
                origin.x: text.implicitHeight / 2
                origin.y: text.implicitHeight / 2
            }
        ]

        width: root.horizontal ? implicitWidth : implicitHeight
        height: root.horizontal ? implicitHeight : implicitWidth

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
