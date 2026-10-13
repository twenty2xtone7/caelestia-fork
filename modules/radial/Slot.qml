pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.effects
import qs.services

// A single radial slot. Its position is animated from the menu origin
// (0,0) out to its radial offset, so items look like they grow out of
// the central anchor instead of merely scaling up.
Item {
    id: root

    required property var itemData
    required property int index
    required property int count
    required property real radius
    required property bool selected
    required property bool expanded
    // Injects the screen-bounds clamp from the host window
    property var clampOffset: (o => o)

    readonly property var offset: clampOffset(Radial.offsetFor(index, count, radius))
    readonly property bool toRight: offset.x >= 0
    readonly property bool toBottom: offset.y > 8

    readonly property real iconSize: Tokens.padding.extraLargeIncreased * 2
    readonly property real hoverScale: selected || hovered ? 1.15 : 1
    property bool hovered: false

    implicitWidth: iconSize
    implicitHeight: iconSize

    // Closed: sits exactly on the origin
    x: Radial.open ? offset.x - width / 2 : -width / 2
    y: Radial.open ? offset.y - height / 2 : -height / 2
    opacity: Radial.open ? 1 : 0
    scale: Radial.open ? hoverScale : 0.4

    Behavior on x {
        Anim {
            type: Anim.Emphasized
        }
    }
    Behavior on y {
        Anim {
            type: Anim.Emphasized
        }
    }
    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
    Behavior on scale {
        Anim {
            type: Anim.Emphasized
        }
    }

    // Icon container
    StyledRect {
        id: iconBox

        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize

        radius: Tokens.rounding.full
        color: root.selected ? Colours.palette.m3primaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)

        Behavior on color {
            CAnim {}
        }

        Elevation {
            anchors.fill: parent
            radius: parent.radius
            level: root.selected ? 2 : 1
        }

        // Material icon underneath, real app icon on top when it resolves
        MaterialIcon {
            anchors.centerIn: parent
            text: Radial.iconName(root.itemData)
            color: root.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.large

            Behavior on color {
                CAnim {}
            }
        }

        // Real application icon on top of the material fallback. SVGs are
        // skipped because they do not render in this Qt build (a broken
        // placeholder would cover the fallback), so those slots keep the
        // material glyph.
        Image {
            id: appIcon

            anchors.centerIn: parent
            width: iconBox.height * 0.6
            height: width
            visible: status === Image.Ready && !/\.svg($|\?)/.test(String(source))

            source: Radial.iconUrl(root.itemData)
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 192
        }

        StateLayer {
            id: hit

            radius: parent.radius
            color: root.selected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface

            onContainsMouseChanged: root.hovered = containsMouse
            onEntered: Radial.selectedIndex = root.index
            onClicked: Radial.activate(root.index)
        }
    }

    // Activation key badge: subtle at idle, prominent on selection, using
    // the same shapes/colours/animations as the rest of the slot.
    StyledRect {
        id: keyBadge

        readonly property string slotKey: Radial.keyFor(root.itemData)

        visible: slotKey !== ""
        anchors.right: iconBox.right
        anchors.top: iconBox.top
        anchors.rightMargin: -Tokens.spacing.extraSmall
        anchors.topMargin: -Tokens.spacing.extraSmall

        implicitHeight: keyLabel.implicitHeight + Tokens.padding.extraSmall * 2
        implicitWidth: Math.max(implicitHeight, keyLabel.implicitWidth + Tokens.padding.small * 2)
        radius: Tokens.rounding.full
        color: root.selected ? Colours.palette.m3primary : Colours.palette.m3tertiaryContainer

        Behavior on color {
            CAnim {}
        }

        StyledText {
            id: keyLabel

            anchors.centerIn: parent
            text: keyBadge.slotKey
            color: root.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onTertiaryContainer
            font: Tokens.font.label.small

            Behavior on color {
                CAnim {}
            }
        }
    }

    // Label: morphs out of the icon on hover, away from the centre
    StyledRect {
        id: labelBox

        readonly property real targetWidth: text.implicitWidth + Tokens.padding.medium * 2

        anchors.verticalCenter: iconBox.verticalCenter
        anchors.left: root.toRight ? iconBox.right : undefined
        anchors.right: root.toRight ? undefined : iconBox.left
        anchors.leftMargin: Tokens.spacing.extraSmall
        anchors.rightMargin: Tokens.spacing.extraSmall

        height: text.implicitHeight + Tokens.padding.extraSmall * 2
        width: root.selected || root.hovered ? targetWidth : 0
        visible: width > 0
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary
        clip: true

        StyledText {
            id: text

            anchors.centerIn: parent
            text: root.itemData?.label ?? ""
            color: Colours.palette.m3onPrimary
            font: Tokens.font.body.small
        }

        Behavior on color {
            CAnim {}
        }

        Behavior on width {
            Anim {
                type: Anim.Emphasized
            }
        }

        Behavior on height {
            Anim {
                type: Anim.Emphasized
            }
        }
    }
}
