import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.Models
import qs.components
import qs.components.effects
import qs.components.images
import qs.services

Item {
    id: root

    required property FileSystemEntry modelData
    required property ScreenState screenState

    scale: 0.5
    opacity: 0
    z: PathView.z ?? 0 // qmllint disable missing-property

    Component.onCompleted: {
        scale = Qt.binding(() => PathView.isCurrentItem ? 1 : PathView.onPath ? 0.8 : 0);
        opacity = Qt.binding(() => PathView.onPath ? 1 : 0);
    }

    implicitWidth: image.width + Tokens.padding.medium * 2
    implicitHeight: image.height + label.height + Tokens.spacing.extraSmall + Tokens.padding.large + Tokens.padding.medium

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            Wallpapers.setWallpaper(root.modelData.path);
            root.screenState.launcher = false;
        }
    }

    Elevation {
        anchors.fill: image
        radius: image.radius
        opacity: root.PathView.isCurrentItem ? 1 : 0
        level: 4

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    StyledClippingRect {
        id: image

        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.padding.large
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large

        implicitWidth: Tokens.sizes.launcher.wallpaperWidth
        implicitHeight: implicitWidth / 16 * 9

        MaterialIcon {
            anchors.centerIn: parent
            text: "image"
            color: Colours.tPalette.m3outline
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).weight(Font.DemiBold).build()
        }

        Image {
            id: wallpaperImage
            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            
            property string videoPath: root.modelData.path
            property bool isVideo: /\.(mp4|webm|mkv|mov|avi|m4v)$/i.test(videoPath)
            
            source: {
                if (isVideo) {
                    // Generate thumbnail path directly
                    const basename = videoPath.split('/').pop().replace(/\.[^.]+$/, '');
                    const thumbPath = `/tmp/caelestia-thumb-${basename}.jpg`;
                    return "file:///" + thumbPath.replace(/^\/+/, "");
                }
                return "file:///" + videoPath.replace(/^\/+/, "");
            }
            
            sourceSize: {
                const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                return Qt.size(image.implicitWidth * dpr, image.implicitHeight * dpr);
            }
        }
        
        // Force Image reload when a thumbnail finishes generating
        Connections {
            target: Wallpapers
            function onThumbnailReady(path) {
                if (path === wallpaperImage.videoPath) {
                    wallpaperImage.status = Image.Loading;
                    const basename = path.split('/').pop().replace(/\.[^.]+$/, '');
                    wallpaperImage.source = "file:///tmp/caelestia-thumb-" + basename + ".jpg";
                }
            }
        }
        
        // Trigger thumbnail generation for videos
        Component.onCompleted: {
            const path = root.modelData.path;
            if (/\.(mp4|webm|mkv|mov|avi|m4v)$/i.test(path)) {
                Wallpapers.getVideoThumbnail(path);
            }
        }

        MaterialIcon {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Tokens.padding.small
            visible: /\.(mp4|webm|mkv|mov|avi|m4v)$/i.test(root.modelData.path)
            text: "movie"
            color: Colours.tPalette.m3onSurface
            fontStyle: Tokens.font.icon.medium
        }
    }

    StyledText {
        id: label

        anchors.top: image.bottom
        anchors.topMargin: Tokens.spacing.extraSmall
        anchors.horizontalCenter: parent.horizontalCenter

        width: image.width - Tokens.padding.medium * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        renderType: Text.QtRendering
        text: root.modelData.relativePath
        font: Tokens.font.label.medium
    }

    Behavior on scale {
        Anim {}
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
