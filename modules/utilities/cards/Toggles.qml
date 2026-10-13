pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus
import qs.modules.bar.popouts as BarPopouts

StyledRect {
    id: root

    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts

    readonly property var quickToggles: {
        const seenIds = new Set();

        return Config.utilities.quickToggles.values.filter(item => {
            if (!item.enabled)
                return false;

            if (seenIds.has(item.id)) {
                return false;
            }

            if (item.id === "vpn") {
                return GlobalConfig.utilities.vpn.selectedProvider.length > 0;
            }

            seenIds.add(item.id);
            return true;
        });
    }
    readonly property int splitIndex: Math.ceil(quickToggles.length / 2)
    readonly property bool needExtraRow: quickToggles.length > 6

    // Night intensity panel expansion (right-click the night toggle)
    property bool nightExpanded: false

    implicitHeight: layout.implicitHeight + Tokens.padding.extraLargeIncreased

    radius: LiquidGlass.enabled ? LiquidGlass.cardRadius : Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    Behavior on implicitHeight {
        Anim {}
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        StyledText {
            text: Tr.tr("Quick toggles")
            font: Tokens.font.body.medium
        }

        QuickToggleRow {
            model: root.needExtraRow ? root.quickToggles.slice(0, root.splitIndex) : root.quickToggles
        }

        QuickToggleRow {
            visible: root.needExtraRow
            model: root.needExtraRow ? root.quickToggles.slice(root.splitIndex) : []
        }

        // Night mode intensity panel: expands on right-click of the night toggle
        Loader {
            id: nightPanel

            Layout.fillWidth: true
            Layout.preferredHeight: root.nightExpanded && item ? item.implicitHeight : 0
            opacity: root.nightExpanded ? 1 : 0
            active: opacity > 0
            visible: active
            asynchronous: false

            Behavior on Layout.preferredHeight {
                Anim {
                    type: Anim.Emphasized
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            sourceComponent: ColumnLayout {
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: Tr.tr("Intensity")
                        font: Tokens.font.body.medium
                    }

                    Item {
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
                    Layout.preferredHeight: Tokens.padding.medium

                    from: 1000
                    to: 6500
                    snapStep: 100
                    value: Night.temperature
                    onInteraction: v => Night.temperature = Math.round(tempSlider.from + v * (tempSlider.to - tempSlider.from))
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
    }

    function presetName(): string {
        for (const preset of Night.presets)
            if (Math.abs(preset.temperature - Night.temperature) < 50)
                return preset.name;
        return Tr.tr("Custom");
    }

    component QuickToggleRow: ButtonRow {
        property alias model: repeater.model

        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            id: repeater

            delegate: DelegateChooser {
                role: "id"

                DelegateChoice {
                    roleValue: "wifi"
                    delegate: Toggle {
                        icon: "wifi"
                        checked: Nmcli.wifiEnabled
                        onClicked: Nmcli.toggleWifi()
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    delegate: Toggle {
                        icon: "bluetooth"
                        checked: Bluetooth.defaultAdapter?.enabled ?? false // qmllint disable unresolved-type
                        onClicked: {
                            const adapter = Bluetooth.defaultAdapter; // qmllint disable unresolved-type
                            if (adapter)
                                adapter.enabled = !adapter.enabled;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "mic"
                    delegate: Toggle {
                        icon: "mic"
                        checked: !Audio.sourceMuted
                        onClicked: {
                            const audio = Audio.source?.audio;
                            if (audio)
                                audio.muted = !audio.muted;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "settings"
                    delegate: Toggle {
                        icon: "settings"
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        isToggle: false
                        onClicked: {
                            root.screenState.utilities = false;
                            WindowFactory.create();
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "gameMode"
                    delegate: Toggle {
                        icon: "gamepad"
                        checked: GameMode.enabled
                        onClicked: GameMode.enabled = !GameMode.enabled
                    }
                }
                DelegateChoice {
                    roleValue: "dnd"
                    delegate: Toggle {
                        icon: "notifications_off"
                        checked: Notifs.dnd
                        onClicked: Notifs.dnd = !Notifs.dnd
                    }
                }
                DelegateChoice {
                    roleValue: "night"
                    delegate: Toggle {
                        icon: "bedtime"
                        checked: Night.enabled
                        onClicked: Night.toggle()

                        // Right-click expands the intensity panel; left-click only toggles.
                        // StateLayer only accepts left clicks, so this never swallows them.
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.nightExpanded = !root.nightExpanded
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "vpn"
                    delegate: Toggle {
                        icon: "vpn_key"
                        checked: VPN.connected && VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                        enabled: !VPN.connecting && !VPN.disconnecting
                        isToggle: VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        onClicked: VPN.toggle()
                    }
                }
                DelegateChoice {
                    roleValue: "restart"
                    delegate: Toggle {
                        icon: "refresh"
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        isToggle: false
                        onClicked: Radial.restartShell()
                    }
                }
            }
        }
    }

    component Toggle: IconButton {
        inactiveColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
        fillWidth: true
        isToggle: true
        isRound: true
        shapeMorph: true
    }
}
