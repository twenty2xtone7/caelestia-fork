import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Delegate for Universal Action Launcher command results. Mirrors AppItem's
// geometry/styling so commands feel like another result type in the existing
// list, but renders a Material symbol and an optional category label.
Item {
    id: root

    required property var modelData
    required property var list

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    readonly property bool disabled: modelData?.enabled === false

    StateLayer {
        radius: LiquidGlass.enabled ? LiquidGlass.controlRadius : Tokens.rounding.large
        onClicked: {
            if (!root.disabled && root.modelData?.onClicked)
                root.modelData.onClicked(root.list);
        }
    }

    // Right-click = secondary action (e.g. the Night mode intensity panel).
    // Left clicks are not accepted here, so they fall through to the
    // StateLayer above this item, matching the quick-toggle night behaviour.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!root.disabled && root.modelData?.onAltClicked)
                root.modelData.onAltClicked(root.list);
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            text: root.modelData?.icon ?? "bolt"
            color: root.disabled ? Colours.palette.m3error : root.modelData?.__command ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
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
                color: root.disabled ? Colours.palette.m3error : Colours.palette.m3onSurface

                anchors.left: parent.left
                anchors.right: category.visible ? category.left : parent.right
                anchors.rightMargin: category.visible ? Tokens.spacing.small : 0
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

            StyledText {
                id: category

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                visible: (root.modelData?.category ?? "") !== ""
                text: root.modelData?.category ?? ""
                font: Tokens.font.label.small
                color: Colours.palette.m3outlineVariant
            }
        }
    }
}
