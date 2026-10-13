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
    property CachingImage fadingImage
    property bool completed

    onSourceChanged: {
        // Fade out old image(s)
        if (current) {
            // If there's already a fading image, destroy it immediately
            if (fadingImage) {
                fadingImage.destroy();
                fadingImage = null;
            }
            fadingImage = current;
            fadingImage.startFadeOut();
            current = null;
        }
        
        if (source && !isLive(source))
            current = imgComp.createObject(this, {
                path: source
            });
        
        // Live wallpapers don't need CachingImage
        if (isLive(source))
            completed = true;
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            if (source && !isLive(source))
                current = imgComp.createObject(this, {
                    path: source
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

    Loader {
        id: liveLoader
        anchors.fill: parent
        active: root.completed && root.isLive(root.source)
        visible: active

        sourceComponent: Component {
            Item {
                anchors.fill: parent

                MediaPlayer {
                    id: vidPlayer
                    property string src: root.source
                    source: src ? ("file://" + src) : ""
                    loops: MediaPlayer.Infinite
                    audioOutput: AudioOutput { muted: true; volume: 0 }
                    videoOutput: vidOut
                    autoPlay: true

                    onSrcChanged: {
                        if (src && vidPlayer.status !== MediaPlayer.Loading) {
                            vidPlayer.source = "file://" + src;
                        }
                    }
                }

                VideoOutput {
                    id: vidOut
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
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
                fadeOutAnim.start();
            }

            onStatusChanged: {
                if (status === Image.Ready)
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
                from: 1
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
