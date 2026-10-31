pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services

// Dyn-Lyrics: Dynamic Island-style pill anchored to the top edge.
// Fixed size by design: no expand/minimize state, so no resize races.
//
// Lyric data comes entirely from Caelestia's Lyrics singleton
// (import Caelestia.Services), the same backend Dashboard/Media uses via
// modules/dashboard/media/LyricList.qml: Lyrics.lyrics, Lyrics.hasLyrics,
// Lyrics.loading and Lyrics.indexForTime(). Track feeding is owned by
// services/Players.qml so nothing here re-requests the same track.
Item {
    id: root
    objectName: "dynLyrics"

    required property ShellScreen screen
    property bool active: false

    readonly property bool isPlaying: Players.active?.isPlaying ?? false
    property real position: 0

    // Read position into a local first: with the call inline inside the
    // ternary QML does not register `root.position` as a binding dependency,
    // so the index freezes at -1 and lyrics never appear.
    readonly property int currentIndex: {
        const pos = root.position;
        const n = Lyrics.lyrics.length;
        return Lyrics.hasLyrics && n > 0 ? Lyrics.indexForTime(pos) : -1;
    }
    readonly property string currentLine: (currentIndex >= 0 && currentIndex < Lyrics.lyrics.length) ? Lyrics.lyrics[currentIndex].trim() : ""

    // Hold the last real line through instrumental gaps instead of blanking out.
    // Reset when the backend swaps tracks so a stale line never sticks.
    property string lastLine: ""
    onCurrentLineChanged: if (currentLine)
        lastLine = currentLine
    Connections {
        target: Lyrics
        function onTrackChanged(): void {
            root.lastLine = "";
        }
    }



    readonly property string displayLine: {
        if (currentLine)
            return currentLine;
        if (Lyrics.loading)
            return "Loading lyrics...";
        if (Lyrics.hasLyrics)
            return lastLine || "♪";
        return "No lyrics available";
    }

    // Single entry point for the slide: every track change, seek, lyric swap
    // or loading-state flip surfaces as a new displayLine.
    onDisplayLineChanged: lyricView.setLine(displayLine)

    // Edge-attached reveal, same as the taskbar popouts and the dashboard:
    // the island no longer draws its own pill. Its surface is a shell-panel
    // BlobRect owned by ContentWindow (dynLyricsBg), so it grows straight out
    // of the edge it hangs from and merges with the bar/border strip instead
    // of floating as a separate rounded pill.
    property real offsetScale: root.active ? 0 : 1
    Behavior on offsetScale {
        Anim {}
    }

    anchors.horizontalCenter: parent.horizontalCenter
    // Panels' origin is the inner edge of the bar/border strip.
    y: 0
    width: Math.min(360, root.screen.width * 0.5)
    // Height drives the background blob, so the whole surface unfurls from
    // the edge rather than just the text sliding in.
    height: 36 * (1 - offsetScale)
    visible: offsetScale < 1
    clip: true
    z: 1000

    Item {
        id: pill

        width: root.width
        height: 36
        // Slips back behind the edge when hidden; the clip + shrinking height
        // on root reveal it from the edge, the way a popout unfolds.
        y: -(height + 5) * root.offsetScale

        // Transparent: the shell-panel blob behind this item is the surface.
        Item {
            anchors.fill: parent

            MaterialIcon {
                id: icon

                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Tokens.padding.medium

                text: "music_note"
                color: Colours.palette.m3primary
            }

            // Per-line slide: two full-width slots. The visible one is stationary;
            // on every line change it slides out left while the other slides in
            // from the right, then both stop until the next index change.
            Item {
                id: lyricView

                anchors.left: icon.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: Tokens.spacing.small
                anchors.rightMargin: Tokens.padding.medium

                clip: true

                property bool usingA: true
                property bool primed: false
                property string shownLine: ""

                function setLine(line: string): void {
                    if (line === shownLine)
                        return;
                    shownLine = line;

                    if (!primed) {
                        primed = true;
                        slotA.text = line;
                        return;
                    }

                    // Rapid index changes must not stack animations: jump the
                    // running one to its end so both slots are settled first.
                    if (slide.running)
                        slide.complete();

                    const out = usingA ? slotA : slotB;
                    const inc = usingA ? slotB : slotA;

                    inc.text = line;
                    inc.x = lyricView.width;
                    inc.opacity = 0;

                    outSlide.target = out;
                    outSlide.from = out.x;
                    outSlide.to = -lyricView.width;
                    outFade.target = out;
                    outFade.from = out.opacity;
                    outFade.to = 0;

                    inSlide.target = inc;
                    inSlide.from = lyricView.width;
                    inSlide.to = 0;
                    inFade.target = inc;
                    inFade.from = 0;
                    inFade.to = 1;

                    usingA = !usingA;
                    slide.restart();
                }

                Component.onCompleted: {
                    slotA.x = 0;
                    slotB.x = lyricView.width;
                    setLine(root.displayLine);
                }

                ParallelAnimation {
                    id: slide

                    Anim {
                        id: outSlide
                        property: "x"
                    }
                    Anim {
                        id: outFade
                        property: "opacity"
                        type: Anim.FastEffects
                    }
                    Anim {
                        id: inSlide
                        property: "x"
                    }
                    Anim {
                        id: inFade
                        property: "opacity"
                        type: Anim.DefaultEffects
                    }
                }

                Item {
                    id: slotA

                    property string text: ""

                    width: lyricView.width
                    height: lyricView.height

                    StyledText {
                        width: parent.width
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font: Tokens.font.body.builders.small.build()
                        color: Colours.palette.m3onSurface
                        text: slotA.text
                    }
                }

                Item {
                    id: slotB

                    property string text: ""

                    width: lyricView.width
                    height: lyricView.height
                    opacity: 0

                    StyledText {
                        width: parent.width
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font: Tokens.font.body.builders.small.build()
                        color: Colours.palette.m3onSurface
                        text: slotB.text
                    }
                }
            }

            StateLayer {
                anchors.fill: parent
                showHoverBackground: false

                acceptedButtons: Qt.RightButton
                onClicked: root.active = false
            }
        }
    }


    // Track sync owned by services/Players.qml; this only polls position.

    // Players.position has no notify signal, so poll it like the dashboard does.
    Timer {
        running: root.active && root.isPlaying
        interval: GlobalConfig.dashboard.mediaUpdateInterval
        triggeredOnStart: true
        repeat: true
        onTriggered: {
            Players.active?.positionChanged();
            root.position = Players.active?.position ?? 0;
        }
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "dynLyrics"
        component: root
    }
}
