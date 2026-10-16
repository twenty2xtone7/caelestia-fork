pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    function isLive(src: string): bool {
        return /\.(mp4|webm|mkv|mov|avi|m4v)$/i.test(src || "");
    }

    property string source: Wallpapers.current
    property CachingImage current
    property Item fadingImage
    property Item liveItem
    property bool completed

    // Only one fading layer at a time: a newer switch destroys the
    // previous fader immediately (same rule as the image path).
    function fadeOutLayer(item) {
        if (!item)
            return;
        if (fadingImage) {
            fadingImage.destroy();
            fadingImage = null;
        }
        fadingImage = item;
        fadingImage.startFadeOut();
    }

    onSourceChanged: {
        // Fade out old layer(s)
        if (current) {
            fadeOutLayer(current);
            current = null;
        }
        if (liveItem) {
            fadeOutLayer(liveItem);
            liveItem = null;
        }

        if (source && !isLive(source))
            current = imgComp.createObject(this, {
                path: source
            });

        // Live wallpapers play in-shell and fade in on first frames,
        // exactly like images fade in on Image.Ready.
        if (isLive(source))
            liveItem = vidComp.createObject(this, {
                srcPath: source
            });

        if (isLive(source))
            completed = true;
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            if (source && !isLive(source))
                current = imgComp.createObject(this, {
                    path: source
                });
            if (isLive(source))
                liveItem = vidComp.createObject(this, {
                    srcPath: source
                });
            completed = true;
        });
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.largeIncreased

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(5).build()
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: Tr.tr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.large.size(28 * 2).weight(Font.Bold).build()
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.extraLargeIncreased
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: Tr.tr("Select a wallpaper")
                            filterLabel: Tr.tr("Image files")
                            filters: Images.validImageExtensions
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: dialog.open()
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: Tr.tr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.body.large
                        }
                    }
                }
            }
        }
    }

    Component {
        id: vidComp

        Item {
            id: vidRoot

            anchors.fill: parent
            opacity: 0

            property string srcPath: ""
            property bool revealed: false

            function startFadeOut() {
                vidFadeIn.stop();
                vidFadeOut.start();
            }

            MediaPlayer {
                id: vidPlayer

                source: vidRoot.srcPath ? ("file://" + vidRoot.srcPath) : ""
                loops: MediaPlayer.Infinite
                audioOutput: AudioOutput {
                    muted: true
                    volume: 0
                }
                videoOutput: vidOut
                autoPlay: true

                onMediaStatusChanged: {
                    // First buffered frames: reveal, mirroring
                    // Image.Ready on the static path. Guarded so a stale
                    // load can't resurrect a superseded video.
                    if (!vidRoot.revealed && root.liveItem === vidRoot
                            && (mediaStatus === MediaPlayer.BufferedMedia || mediaStatus === MediaPlayer.LoadedMedia)) {
                        vidRoot.revealed = true;
                        vidFadeIn.start();
                    }
                }
            }

            VideoOutput {
                id: vidOut

                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }

            Anim on opacity {
                id: vidFadeIn

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Anim on opacity {
                id: vidFadeOut

                type: Anim.SlowEffects
                running: false
                // No `from`: same stale-flash rationale as the image path.
                to: 0
                onFinished: {
                    if (root.fadingImage === vidRoot) {
                        root.fadingImage.destroy();
                        root.fadingImage = null;
                    }
                }
            }
        }
    }

    Component {
        id: imgComp

        CachingImage {
            id: img

            anchors.fill: parent

            opacity: 0

            function startFadeOut() {
                // Stop a pending fade-in first: without this, a late
                // Image.Ready on a stale layer restarts the fade-in and
                // the old wallpaper flashes back mid-transition (e.g.
                // rapid A → B → C switching resurrects B).
                anim.stop();
                fadeOutAnim.start();
            }

            onStatusChanged: {
                // Only reveal while still the current layer — a stale
                // async load must never fade a superseded wallpaper in.
                if (status === Image.Ready && root.current === img)
                    anim.start();
            }

            Anim on opacity {
                id: anim

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Anim on opacity {
                id: fadeOutAnim

                type: Anim.SlowEffects
                running: false
                // No `from`: a never-revealed layer fades from its actual
                // (transparent) opacity instead of flashing to 1 first.
                to: 0
                onFinished: {
                    if (root.fadingImage === img) {
                        root.fadingImage.destroy();
                        root.fadingImage = null;
                    }
                }
            }
        }
    }
}
