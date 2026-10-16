pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Bar-position picker, opened from the taskbar logo. Styled and animated like
// the other taskbar popouts: it grows/shrinks through the shared popout
// Wrapper, and the option buttons highlight the active position.
//
// Stage 1: Top and Left are functional. Bottom and Right are shown as disabled
// placeholders so the panel remains extendable when they are wired up.
ColumnLayout {
    id: root

    required property PopoutState popouts

    spacing: Tokens.spacing.small
    width: Tokens.sizes.bar.kbLayoutWidth

    readonly property var options: [
        {
            value: "top",
            icon: "arrow_upward",
            label: Tr.tr("Top"),
            enabled: true
        },
        {
            value: "bottom",
            icon: "arrow_downward",
            label: Tr.tr("Bottom"),
            enabled: false
        },
        {
            value: "left",
            icon: "arrow_back",
            label: Tr.tr("Left"),
            enabled: true
        },
        {
            value: "right",
            icon: "arrow_forward",
            label: Tr.tr("Right"),
            enabled: false
        }
    ]

    StyledText {
        Layout.topMargin: Tokens.padding.medium
        Layout.rightMargin: Tokens.padding.extraSmall
        text: Tr.tr("Taskbar position")
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: Tokens.padding.extraSmall
        columns: 2
        columnSpacing: Tokens.spacing.small
        rowSpacing: Tokens.spacing.small

        Repeater {
            model: root.options

            PositionButton {
                required property var modelData

                Layout.fillWidth: true
                position: modelData.value
                icon: modelData.icon
                label: modelData.label
                enabled: modelData.enabled
            }
        }
    }

    component PositionButton: Item {
        id: btn

        required property string position
        required property string icon
        required property string label
        required property bool enabled

        readonly property bool active: BarState.position === btn.position

        implicitWidth: inner.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2
        Layout.fillWidth: true

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.large
            color: btn.active
                  ? (btn.enabled ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer)
                  : Colours.tPalette.m3surfaceContainer
            opacity: btn.enabled ? 1 : 0.45

            Behavior on color {
                CAnim {}
            }
        }

        StateLayer {
            anchors.fill: parent
            radius: Tokens.rounding.large
            enabled: btn.enabled
            onClicked: {
                BarState.setPosition(btn.position);
                // Auto-close the panel once a position is applied
                root.popouts.hasCurrent = false;
            }
        }

        ColumnLayout {
            id: inner

            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: btn.icon
                color: btn.active
                      ? (btn.enabled ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant)
                      : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium

                Behavior on color {
                    CAnim {}
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: btn.label
                color: btn.active
                      ? (btn.enabled ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant)
                      : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.build()

                Behavior on color {
                    CAnim {}
                }
            }
        }
    }
}
