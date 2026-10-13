pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Built-in player for screen recordings: play(path) starts playback right
// here, so no external app is needed. Close stops and unloads the media.
// An "open externally" button stays as a fallback.
StyledRect {
    id: root

    signal closeRequested

    property string currentPath: ""
    property string errorText: ""

    readonly property string currentName: currentPath.split("/").pop()

    function play(path: string): void {
        player.stop();
        root.errorText = "";
        root.currentPath = path;
        player.source = `file://${path}`;
        root.visible = true;
        player.play();
    }

    function close(): void {
        player.stop();
        player.source = "";
        root.currentPath = "";
        root.visible = false;
        closeRequested();
    }

    function fmt(ms: real): string {
        if (!(ms > 0))
            return "0:00";
        const s = Math.floor(ms / 1000);
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    visible: false
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2

    MediaPlayer {
        id: player

        audioOutput: AudioOutput {
            id: audioOut
        }
        videoOutput: videoOut

        // qmllint disable signal-handler-parameters
        onErrorOccurred: (error, errorString) => {
            root.errorText = errorString || Tr.tr("Playback failed");
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia)
                player.pause();
            // Sound diagnostics: track count + output state land in the
            // shell log on every load so silent playback is traceable.
            if (mediaStatus === MediaPlayer.LoadedMedia)
                console.info(`[VideoPlayer] loaded audioTracks=${player.audioTracks.length} hasAudio=${player.hasAudio} muted=${audioOut.muted} volume=${audioOut.volume}`);
        }
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "movie"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.currentName
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            IconButton {
                icon: "open_in_new"
                type: IconButton.Text
                enabled: root.currentPath !== ""
                onClicked: Quickshell.execDetached([...GlobalConfig.general.apps.playback, root.currentPath])
                Layout.alignment: Qt.AlignVCenter
            }

            IconButton {
                icon: "close"
                type: IconButton.Text
                onClicked: root.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: Math.round(width * 9 / 16)
            radius: Tokens.rounding.medium
            color: "black"

            VideoOutput {
                id: videoOut

                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectFit
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (player.playbackState === MediaPlayer.PlayingState)
                        player.pause();
                    else
                        player.play();
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: player.playbackState !== MediaPlayer.PlayingState && !root.errorText
                text: player.playbackState === MediaPlayer.PausedState ? "pause_circle" : "play_circle"
                color: Qt.alpha(Colours.palette.m3onSurface, 0.8)
                fontStyle: Tokens.font.icon.extraLarge
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconButton {
                icon: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
                type: IconButton.Tonal
                enabled: player.seekable || player.playbackState === MediaPlayer.PlayingState || player.position > 0
                onClicked: {
                    if (player.playbackState === MediaPlayer.PlayingState)
                        player.pause();
                    else
                        player.play();
                }
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: root.fmt(player.position)
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurface
            }

            StyledSlider {
                id: seek

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                from: 0
                to: Math.max(1, player.duration)
                value: Math.min(player.position, to)
                enabled: player.duration > 0
                interactionOnMove: false
                // interaction() reports a normalised 0..1 position,
                // not milliseconds: scale it to the duration.
                onInteraction: v => player.position = v * Math.max(1, player.duration)
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: root.fmt(player.duration)
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurface
            }
        }

        StyledText {
            visible: root.errorText !== ""
            Layout.fillWidth: true
            text: root.errorText
            font: Tokens.font.label.small
            color: Colours.palette.m3error
            wrapMode: Text.WordWrap
        }
    }
}
