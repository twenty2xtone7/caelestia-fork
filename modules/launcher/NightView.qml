pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

// Night-mode mini-app. Opened by right-clicking the "Night mode" command
// result in the launcher (left-click still just toggles on/off). Escape or
// the X button morphs back to the result list.
//
// This reuses the existing Night service (qs.services.Night) - the same
// backend the quick-toggle intensity panel uses - so there is no duplicated
// night-light logic.
Item {
    id: root

    required property var screenState
    required property SearchBar search

    signal closeRequested

    focus: true

    function backToActions(): void {
        Actions.closeMiniApp();
        search.text = GlobalConfig.launcher.actionPrefix;
        search.forceActiveFocus();
        closeRequested();
    }

    function presetName(): string {
        for (const preset of Night.presets)
            if (Math.abs(preset.temperature - Night.temperature) < 50)
                return preset.name;
        return Tr.tr("Custom");
    }

    implicitWidth: Tokens.sizes.launcher.itemWidth * 1.2
    implicitHeight: layout.implicitHeight

    Component.onCompleted: root.forceActiveFocus()

    Keys.onEscapePressed: backToActions()

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right

        spacing: Tokens.spacing.medium

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "nightlight"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.large
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: Tr.tr("Night mode")
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
            }

            IconButton {
                icon: "close"
                type: IconButton.Text
                onClicked: root.backToActions()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Enable toggle
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: Tr.tr("Enabled")
                font: Tokens.font.body.medium
                Layout.fillWidth: true
            }

            StyledSwitch {
                checked: Night.enabled
                onToggled: Night.enabled = checked
            }
        }

        // Intensity
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: Tr.tr("Intensity")
                font: Tokens.font.body.medium
                Layout.fillWidth: true
            }

            StyledText {
                text: Tr.trCtx("%1K · %2", "night mode temperature and preset").arg(Night.temperature).arg(root.presetName())
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

        StyledSlider {
            id: tempSlider

            Layout.fillWidth: true
            Layout.preferredHeight: 20

            from: 1000
            to: 6500
            snapStep: 100
            value: Night.temperature
            onInteraction: v => {
                Night.temperature = Math.round(tempSlider.from + v * (tempSlider.to - tempSlider.from));
                Night.enabled = true;
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: Night.presets

                TextButton {
                    required property var modelData

                    Layout.fillWidth: true
                    type: Night.temperature === modelData.temperature ? TextButton.Filled : TextButton.Tonal
                    verticalPadding: Tokens.padding.extraSmall
                    font: Tokens.font.body.small
                    text: Tr.trCtx("%1K", "night mode preset temperature").arg(modelData.temperature)
                    onClicked: {
                        Night.temperature = modelData.temperature;
                        Night.enabled = true;
                    }
                }
            }
        }
    }
}
