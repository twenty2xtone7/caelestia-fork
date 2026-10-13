pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Liquid Glass")

    readonly property list<MenuItem> presetItems: [
        MenuItem { text: Tr.tr("Default"); value: "Default" },
        MenuItem { text: Tr.tr("Clear Glass"); value: "Clear Glass" },
        MenuItem { text: Tr.tr("Frosted Glass"); value: "Frosted Glass" },
        MenuItem { text: Tr.tr("Deep Glass"); value: "Deep Glass" },
        MenuItem { text: Tr.tr("Acrylic"); value: "Acrylic" },
        MenuItem { text: Tr.tr("Liquid"); value: "Liquid" },
        MenuItem { text: Tr.tr("Minimal"); value: "Minimal" },
        MenuItem { text: Tr.tr("Custom"); value: "Custom" }
    ]

    readonly property MenuItem activePresetItem: {
        for (const item of root.presetItems) {
            if (item.value === LiquidGlass.activePreset)
                return item;
        }
        return root.presetItems[0];
    }

    readonly property list<MenuItem> componentItems: [
        MenuItem { text: Tr.tr("Bar"); value: "bar" },
        MenuItem { text: Tr.tr("Launcher"); value: "launcher" },
        MenuItem { text: Tr.tr("Sidebar"); value: "sidebar" },
        MenuItem { text: Tr.tr("Dashboard"); value: "dashboard" },
        MenuItem { text: Tr.tr("Notifications"); value: "notifications" },
        MenuItem { text: Tr.tr("OSD"); value: "osd" },
        MenuItem { text: Tr.tr("Menus"); value: "menus" },
        MenuItem { text: Tr.tr("Dialogs"); value: "dialogs" }
    ]

    property string overrideTarget: "bar"

    readonly property MenuItem activeComponentItem: {
        for (const item of root.componentItems) {
            if (item.value === root.overrideTarget)
                return item;
        }
        return root.componentItems[0];
    }

    function markCustom(): void {
        if (LiquidGlass.activePreset !== "Custom")
            LiquidGlass.activePreset = "Custom";
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            last: true
            text: Tr.tr("Enable Liquid Glass")
            subtext: Tr.tr("Apply the glass material to shell surfaces")
            checked: LiquidGlass.enabled
            onToggled: LiquidGlass.enabled = checked
        }

        // Preview
        SectionHeader {
            text: Tr.tr("Preview")
        }

        GlassSurface {
            Layout.fillWidth: true
            Layout.preferredHeight: previewCol.implicitHeight + Tokens.padding.large * 2
            radiusGroup: "card"
            elevation: 2
            color: Colours.tPalette.m3surfaceContainer
            clip: true

            ColumnLayout {
                id: previewCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    text: Tr.tr("Glass card")
                    font: Tokens.font.title.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Changes apply to the whole shell immediately.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    spacing: Tokens.spacing.small

                    IconTextButton {
                        icon: "play_arrow"
                        text: Tr.tr("Play")
                        type: IconTextButton.Filled
                        isRound: true
                    }

                    IconButton {
                        icon: "favorite"
                        type: IconButton.Tonal
                        isRound: true
                        isToggle: true
                    }

                    StyledSwitch {
                        checked: true
                    }
                }

                StyledSlider {
                    Layout.fillWidth: true
                    implicitHeight: Tokens.padding.medium * 2
                    value: LiquidGlass.opacity
                    enabled: false
                }
            }
        }

        // Presets
        SectionHeader {
            text: Tr.tr("Presets")
        }

        SelectRow {
            first: true
            label: Tr.tr("Preset")
            subtext: Tr.tr("Starting point. Editing sliders keeps your changes.")
            menuItems: root.presetItems
            active: root.activePresetItem
            onSelected: item => {
                if (item.value !== "Custom")
                    LiquidGlass.applyPreset(item.value);
            }
        }

        TextFieldRow {
            label: Tr.tr("Save as custom preset")
            subtext: Tr.tr("Name, then press enter")
            placeholderText: Tr.tr("My glass")
            maximumLength: 32
            onEditingFinished: text => {
                const name = text.trim();
                if (name.length > 0)
                    LiquidGlass.saveAsPreset(name);
            }
        }

        Repeater {
            model: Object.keys(LiquidGlass.userPresets)

            RowButton {
                required property string modelData

                icon: "bookmark"
                text: modelData
                subtext: Tr.tr("Click to apply this saved preset")
                onClicked: LiquidGlass.applyPreset(modelData)
            }
        }

        RowButton {
            visible: LiquidGlass.userPresets[LiquidGlass.activePreset] !== undefined
            icon: "delete"
            text: Tr.tr("Delete this saved preset")
            subtext: LiquidGlass.activePreset
            onClicked: LiquidGlass.deleteUserPreset(LiquidGlass.activePreset)
        }

        RowButton {
            last: true
            icon: "restart_alt"
            text: Tr.tr("Reset all")
            subtext: Tr.tr("Restore Default preset and clear overrides")
            onClicked: LiquidGlass.resetDefaults()
        }

        // Material
        SectionHeader {
            text: Tr.tr("Material")
        }

        SliderRow {
            first: true
            icon: "opacity"
            label: Tr.tr("Glass Opacity")
            valueLabel: Strings.percentOne(value)
            value: (LiquidGlass.opacity - 0.1) / 0.9
            onMoved: v => {
                LiquidGlass.opacity = 0.1 + v * 0.9;
                root.markCustom();
            }
        }

        SliderRow {
            icon: "palette"
            label: Tr.tr("Surface Tint")
            valueLabel: Strings.percentOne(value)
            value: LiquidGlass.tint
            onMoved: v => {
                LiquidGlass.tint = v;
                root.markCustom();
            }
        }

        SliderRow {
            icon: "filter_vintage"
            label: Tr.tr("Saturation")
            valueLabel: (value * 2).toFixed(2)
            value: LiquidGlass.saturation / 2
            onMoved: v => {
                LiquidGlass.saturation = v * 2;
                root.markCustom();
            }
        }

        SliderRow {
            icon: "wb_sunny"
            label: Tr.tr("Brightness")
            valueLabel: LiquidGlass.brightness.toFixed(2)
            value: (LiquidGlass.brightness - 0.5)
            onMoved: v => {
                LiquidGlass.brightness = 0.5 + v;
                root.markCustom();
            }
        }

        SliderRow {
            last: true
            icon: "contrast"
            label: Tr.tr("Contrast")
            valueLabel: LiquidGlass.contrast.toFixed(2)
            value: (LiquidGlass.contrast - 0.5)
            onMoved: v => {
                LiquidGlass.contrast = 0.5 + v;
                root.markCustom();
            }
        }

        RowButton {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            first: true
            last: true
            icon: "restart_alt"
            text: Tr.tr("Reset Material")
            onClicked: LiquidGlass.resetSection("material")
        }

        // Depth
        SectionHeader {
            text: Tr.tr("Depth")
        }

        SliderRow {
            first: true
            icon: "border_style"
            label: Tr.tr("Border Strength")
            valueLabel: Strings.percentOne(value)
            value: LiquidGlass.borderOpacity
            onMoved: v => {
                LiquidGlass.borderOpacity = v;
                root.markCustom();
            }
        }

        SliderRow {
            icon: "highlight"
            label: Tr.tr("Highlight Strength")
            valueLabel: Strings.percentOne(value)
            value: LiquidGlass.highlightOpacity
            onMoved: v => {
                LiquidGlass.highlightOpacity = v;
                root.markCustom();
            }
        }

        SliderRow {
            icon: "blur_on"
            label: Tr.tr("Shadow Strength")
            valueLabel: Strings.percentOne(value)
            value: LiquidGlass.shadowOpacity
            onMoved: v => {
                LiquidGlass.shadowOpacity = v;
                root.markCustom();
            }
        }

        SliderRow {
            icon: "blur_circular"
            label: Tr.tr("Shadow Softness")
            valueLabel: Math.round(LiquidGlass.shadowBlur).toString()
            value: LiquidGlass.shadowBlur / 48
            onMoved: v => {
                LiquidGlass.shadowBlur = v * 48;
                root.markCustom();
            }
        }

        ToggleRow {
            last: true
            text: Tr.tr("Inner Highlight")
            subtext: Tr.tr("Faint rim inside the glass edge")
            checked: LiquidGlass.innerHighlight
            onToggled: {
                LiquidGlass.innerHighlight = checked;
                root.markCustom();
            }
        }

        RowButton {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            first: true
            last: true
            icon: "restart_alt"
            text: Tr.tr("Reset Depth")
            onClicked: LiquidGlass.resetSection("depth")
        }

        // Shape
        SectionHeader {
            text: Tr.tr("Shape")
        }

        SliderRow {
            first: true
            icon: "rounded_corner"
            label: Tr.tr("Corner Radius")
            valueLabel: Math.round(LiquidGlass.cornerRadius).toString()
            value: LiquidGlass.cornerRadius / 48
            onMoved: v => {
                LiquidGlass.cornerRadius = v * 48;
                root.markCustom();
            }
        }

        SliderRow {
            icon: "crop_square"
            label: Tr.tr("Card Radius")
            valueLabel: Math.round(LiquidGlass.cardRadius).toString()
            value: LiquidGlass.cardRadius / 48
            onMoved: v => {
                LiquidGlass.cardRadius = v * 48;
                root.markCustom();
            }
        }

        SliderRow {
            icon: "smart_button"
            label: Tr.tr("Control Radius")
            valueLabel: Math.round(LiquidGlass.controlRadius).toString()
            value: LiquidGlass.controlRadius / 48
            onMoved: v => {
                LiquidGlass.controlRadius = v * 48;
                root.markCustom();
            }
        }

        SliderRow {
            last: true
            icon: "web_asset"
            label: Tr.tr("Popup Radius")
            valueLabel: Math.round(LiquidGlass.popupRadius).toString()
            value: LiquidGlass.popupRadius / 48
            onMoved: v => {
                LiquidGlass.popupRadius = v * 48;
                root.markCustom();
            }
        }

        RowButton {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            first: true
            last: true
            icon: "restart_alt"
            text: Tr.tr("Reset Shape")
            onClicked: LiquidGlass.resetSection("shape")
        }

        // Motion
        SectionHeader {
            text: Tr.tr("Motion")
        }

        SliderRow {
            first: true
            icon: "animation"
            label: Tr.tr("Animation Intensity")
            valueLabel: Strings.percentOne(value)
            value: LiquidGlass.animationIntensity
            onMoved: v => {
                LiquidGlass.animationIntensity = v;
                root.markCustom();
            }
        }

        SliderRow {
            icon: "speed"
            label: Tr.tr("Animation Speed")
            valueLabel: LiquidGlass.animationSpeed.toFixed(2) + "×"
            value: (LiquidGlass.animationSpeed - 0.25) / 2.75
            onMoved: v => {
                LiquidGlass.animationSpeed = 0.25 + v * 2.75;
                root.markCustom();
            }
        }

        SliderRow {
            icon: "touch_app"
            label: Tr.tr("Hover Intensity")
            valueLabel: Strings.percentOne(value)
            value: LiquidGlass.hoverIntensity
            onMoved: v => {
                LiquidGlass.hoverIntensity = v;
                root.markCustom();
            }
        }

        SliderRow {
            last: true
            icon: "ads_click"
            label: Tr.tr("Press Intensity")
            valueLabel: Strings.percentOne(value)
            value: LiquidGlass.pressIntensity
            onMoved: v => {
                LiquidGlass.pressIntensity = v;
                root.markCustom();
            }
        }

        RowButton {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            first: true
            last: true
            icon: "restart_alt"
            text: Tr.tr("Reset Motion")
            onClicked: LiquidGlass.resetSection("motion")
        }

        // Component overrides
        SectionHeader {
            text: Tr.tr("Component Overrides")
        }

        SelectRow {
            first: true
            label: Tr.tr("Component")
            subtext: Tr.tr("Optional per-surface tweaks. Global settings stay the default.")
            menuItems: root.componentItems
            active: root.activeComponentItem
            onSelected: item => root.overrideTarget = item.value
        }

        ToggleRow {
            text: Tr.tr("Use global settings")
            subtext: Tr.tr("Disable to set opacity, radius, border, and shadow for this surface")
            checked: LiquidGlass.componentUsesGlobal(root.overrideTarget)
            onToggled: {
                if (checked)
                    LiquidGlass.useGlobalForComponent(root.overrideTarget);
                else
                    LiquidGlass.setOverride(root.overrideTarget, "opacity", LiquidGlass.opacity);
            }
        }

        SliderRow {
            enabled: !LiquidGlass.componentUsesGlobal(root.overrideTarget)
            opacity: enabled ? 1 : 0.4
            icon: "opacity"
            label: Tr.tr("Opacity")
            valueLabel: Strings.percentOne(LiquidGlass.effectiveValue("opacity", root.overrideTarget))
            value: (LiquidGlass.effectiveValue("opacity", root.overrideTarget) - 0.1) / 0.9
            onMoved: v => LiquidGlass.setOverride(root.overrideTarget, "opacity", 0.1 + v * 0.9)
        }

        SliderRow {
            enabled: !LiquidGlass.componentUsesGlobal(root.overrideTarget)
            opacity: enabled ? 1 : 0.4
            icon: "rounded_corner"
            label: Tr.tr("Radius")
            valueLabel: Math.round(LiquidGlass.effectiveValue("cardRadius", root.overrideTarget)).toString()
            value: LiquidGlass.effectiveValue("cardRadius", root.overrideTarget) / 48
            onMoved: v => LiquidGlass.setOverride(root.overrideTarget, "cardRadius", v * 48)
        }

        SliderRow {
            enabled: !LiquidGlass.componentUsesGlobal(root.overrideTarget)
            opacity: enabled ? 1 : 0.4
            icon: "border_style"
            label: Tr.tr("Border")
            valueLabel: Strings.percentOne(LiquidGlass.effectiveValue("borderOpacity", root.overrideTarget))
            value: LiquidGlass.effectiveValue("borderOpacity", root.overrideTarget)
            onMoved: v => LiquidGlass.setOverride(root.overrideTarget, "borderOpacity", v)
        }

        SliderRow {
            last: true
            enabled: !LiquidGlass.componentUsesGlobal(root.overrideTarget)
            opacity: enabled ? 1 : 0.4
            icon: "blur_on"
            label: Tr.tr("Shadow")
            valueLabel: Strings.percentOne(LiquidGlass.effectiveValue("shadowOpacity", root.overrideTarget))
            value: LiquidGlass.effectiveValue("shadowOpacity", root.overrideTarget)
            onMoved: v => LiquidGlass.setOverride(root.overrideTarget, "shadowOpacity", v)
        }

        // Import / Export
        SectionHeader {
            text: Tr.tr("Import / Export")
        }

        RowButton {
            first: true
            icon: "content_copy"
            text: Tr.tr("Copy preset JSON")
            subtext: Tr.tr("Copy the current Liquid Glass config to the clipboard")
            onClicked: Quickshell.clipboardText = LiquidGlass.exportConfig()
        }

        TextFieldRow {
            last: true
            label: Tr.tr("Import preset JSON")
            subtext: Tr.tr("Paste JSON, then press enter")
            placeholderText: "{ ... }"
            onEditingFinished: text => {
                if (text.trim().length > 0)
                    LiquidGlass.importConfig(text);
            }
        }
    }
}
