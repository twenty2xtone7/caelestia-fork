import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property var modelData
    required property var list

    readonly property string title: root.modelData?.title ?? ""
    readonly property string artist: root.modelData?.artist ?? ""
    readonly property int duration: root.modelData?.duration ?? 0

    function fmtDuration(secs: int): string {
        if (!secs || secs <= 0)
            return "";
        const m = Math.floor(secs / 60);
        const s = secs % 60;
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }

    function play(): void {
        MusicService.resolveAndPlay(root.modelData);
    }

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: root.play()
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            text: "music_note"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: queueBtn.left
            anchors.rightMargin: Tokens.spacing.small
            anchors.verticalCenter: icon.verticalCenter

            implicitWidth: parent.width - icon.width
            implicitHeight: name.implicitHeight + desc.implicitHeight

            StyledText {
                id: name

                text: root.title
                font: Tokens.font.body.medium

                anchors.left: parent.left
                anchors.right: parent.right
                elide: Text.ElideRight
            }

            StyledText {
                id: desc

                text: root.fmtDuration(root.duration) ? `${root.artist} • ${root.fmtDuration(root.duration)}` : root.artist
                font: Tokens.font.body.small
                color: Colours.palette.m3outline

                elide: Text.ElideRight
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: name.bottom
            }
        }

        IconButton {
            id: queueBtn

            anchors.right: downloadBtn.left
            anchors.rightMargin: Tokens.spacing.small
            anchors.verticalCenter: parent.verticalCenter

            icon: "playlist_add"
            type: IconButton.Text
            onClicked: MusicService.enqueue(root.modelData)
        }

        IconButton {
            id: downloadBtn

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            icon: "download"
            type: IconButton.Text
            onClicked: MusicService.download(root.modelData)
        }
    }
}
