import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData
    required property var list

    // The translate/music mini-app entries morph the launcher instead of
    // running a process, so they get the same trailing affordance.
    readonly property bool isTranslate: {
        const cmd = root.modelData?.command;
        return !!cmd && cmd.length > 0 && (cmd[0] === "translate" || cmd[0] === "music" || cmd[0] === "clipboard");
    }

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: root.modelData?.onClicked(root.list)
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            text: root.modelData?.icon ?? ""
            color: isTranslate ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: icon.verticalCenter

            implicitWidth: parent.width - icon.width
            implicitHeight: name.implicitHeight + desc.implicitHeight

            StyledText {
                id: name

                text: root.modelData?.name ?? ""
                font: Tokens.font.body.medium

                anchors.left: parent.left
                anchors.right: chevron.visible ? chevron.left : parent.right
                anchors.rightMargin: chevron.visible ? Tokens.spacing.small : 0
                elide: Text.ElideRight
            }

            StyledText {
                id: desc

                text: root.modelData?.desc ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3outline

                elide: Text.ElideRight
                width: root.width - icon.width - Tokens.rounding.extraLargeIncreased

                anchors.top: name.bottom
            }

            // Marks the entry that morphs the launcher into the translate
            // mini-app (mirrors the old command-row affordance).
            MaterialIcon {
                id: chevron

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                visible: isTranslate
                text: "arrow_outward"
                color: Colours.palette.m3outline
                fontStyle: Tokens.font.icon.medium
            }
        }
    }
}
