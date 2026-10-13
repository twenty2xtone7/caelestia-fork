pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> shapeItems: [
        MenuItem {
            text: Tr.trCtx("Round", "snowflake shape")
        },
        MenuItem {
            text: Tr.trCtx("Square", "snowflake shape")
        }
    ]

    title: Tr.tr("Snow")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // General
        SectionHeader {
            first: true
            text: Tr.tr("General")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Enable snow")
            subtext: Tr.tr("Show falling snow on the desktop")
            checked: Snow.enabled
            onToggled: Snow.enabled = checked
        }

        StepperRow {
            label: Tr.tr("Flake count")
            subtext: Tr.tr("Number of snowflakes per screen")
            value: Snow.count
            from: 0
            to: 1000
            stepSize: 10
            onMoved: v => Snow.count = Math.round(v)
        }

        SelectRow {
            label: Tr.tr("Flake shape")
            subtext: Tr.tr("Shape of each snowflake")
            menuItems: root.shapeItems
            active: root.shapeItems[Snow.shape] ?? root.shapeItems[0]
            onSelected: item => Snow.shape = root.shapeItems.indexOf(item)
        }

        TextFieldRow {
            last: true
            label: Tr.tr("Flake colour")
            subtext: Tr.tr("Hex colour, e.g. #ffffff")
            value: Snow.color
            placeholderText: "#ffffff"
            maximumLength: 7
            errorText: Tr.tr("Must be a hex colour like #ffffff")
            validate: text => /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$/.test(text)
            onEditingFinished: text => {
                if (/^#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$/.test(text))
                    Snow.color = text;
            }
        }

        // Flakes
        SectionHeader {
            text: Tr.tr("Flakes")
        }

        StepperRow {
            first: true
            label: Tr.tr("Min size")
            subtext: Tr.tr("Smallest flake size (px)")
            value: Snow.minSize
            from: 1
            to: 30
            stepSize: 0.5
            onMoved: v => {
                Snow.minSize = v;
                if (Snow.maxSize < v)
                    Snow.maxSize = v;
            }
        }

        StepperRow {
            label: Tr.tr("Max size")
            subtext: Tr.tr("Largest flake size (px)")
            value: Snow.maxSize
            from: 1
            to: 30
            stepSize: 0.5
            onMoved: v => {
                Snow.maxSize = v;
                if (Snow.minSize > v)
                    Snow.minSize = v;
            }
        }

        SliderRow {
            icon: "opacity"
            label: Tr.tr("Min opacity")
            valueLabel: Strings.percentOne(value)
            value: Snow.minOpacity
            onMoved: v => {
                Snow.minOpacity = v;
                if (Snow.maxOpacity < v)
                    Snow.maxOpacity = v;
            }
        }

        SliderRow {
            last: true
            icon: "opacity"
            label: Tr.tr("Max opacity")
            valueLabel: Strings.percentOne(value)
            value: Snow.maxOpacity
            onMoved: v => {
                Snow.maxOpacity = v;
                if (Snow.minOpacity > v)
                    Snow.minOpacity = v;
            }
        }

        // Motion
        SectionHeader {
            text: Tr.tr("Motion")
        }

        StepperRow {
            first: true
            label: Tr.tr("Min fall speed")
            subtext: Tr.tr("Slowest fall speed (px/s)")
            value: Snow.minSpeed
            from: 5
            to: 800
            stepSize: 5
            onMoved: v => {
                Snow.minSpeed = v;
                if (Snow.maxSpeed < v)
                    Snow.maxSpeed = v;
            }
        }

        StepperRow {
            label: Tr.tr("Max fall speed")
            subtext: Tr.tr("Fastest fall speed (px/s)")
            value: Snow.maxSpeed
            from: 5
            to: 800
            stepSize: 5
            onMoved: v => {
                Snow.maxSpeed = v;
                if (Snow.minSpeed > v)
                    Snow.minSpeed = v;
            }
        }

        StepperRow {
            label: Tr.tr("Wind")
            subtext: Tr.tr("Horizontal drift, negative blows left")
            value: Snow.wind
            from: -1
            to: 1
            stepSize: 0.05
            onMoved: v => Snow.wind = v
        }

        StepperRow {
            label: Tr.tr("Sway")
            subtext: Tr.tr("Side-to-side sway amplitude (px)")
            value: Snow.sway
            from: 0
            to: 300
            stepSize: 1
            onMoved: v => Snow.sway = v
        }

        StepperRow {
            label: Tr.tr("Sway speed")
            subtext: Tr.tr("How fast flakes sway (oscillations/s)")
            value: Snow.swaySpeed
            from: 0
            to: 5
            stepSize: 0.1
            onMoved: v => Snow.swaySpeed = v
        }

        ToggleRow {
            text: Tr.tr("Spin")
            subtext: Tr.tr("Rotate flakes while they fall")
            checked: Snow.spin
            onToggled: Snow.spin = checked
        }

        StepperRow {
            label: Tr.tr("Spin speed")
            subtext: Tr.tr("Maximum rotation speed (deg/s)")
            value: Snow.spinSpeed
            from: 0
            to: 720
            stepSize: 5
            onMoved: v => Snow.spinSpeed = v
        }

        ToggleRow {
            text: Tr.tr("Depth effect")
            subtext: Tr.tr("Bigger flakes fall faster")
            checked: Snow.depth
            onToggled: Snow.depth = checked
        }

        // Lifetime decay
        SectionHeader {
            text: Tr.tr("Lifetime")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Flake decay")
            subtext: Tr.tr("Flakes shrink away after their lifetime")
            checked: Snow.decayEnabled
            onToggled: Snow.decayEnabled = checked
        }

        StepperRow {
            label: Tr.tr("Min lifetime")
            subtext: Tr.tr("Shortest life before shrinking (s)")
            value: Snow.minLifetime
            from: 1
            to: 300
            stepSize: 1
            onMoved: v => {
                Snow.minLifetime = v;
                if (Snow.maxLifetime < v)
                    Snow.maxLifetime = v;
            }
        }

        StepperRow {
            label: Tr.tr("Max lifetime")
            subtext: Tr.tr("Longest life before shrinking (s)")
            value: Snow.maxLifetime
            from: 1
            to: 300
            stepSize: 1
            onMoved: v => {
                Snow.maxLifetime = v;
                if (Snow.minLifetime > v)
                    Snow.minLifetime = v;
            }
        }

        StepperRow {
            last: true
            label: Tr.tr("Shrink duration")
            subtext: Tr.tr("How long shrinking takes (s)")
            value: Snow.shrinkTime
            from: 0.1
            to: 30
            stepSize: 0.1
            onMoved: v => Snow.shrinkTime = v
        }

        NavRow {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            last: true
            trailingIcon: ""
            icon: "restart_alt"
            text: Tr.tr("Reset to defaults")
            subtext: Tr.tr("Restore the default snow settings")
            onClicked: Snow.resetDefaults()
        }
    }
}
