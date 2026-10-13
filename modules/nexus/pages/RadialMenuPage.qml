pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property int selected: -1
    property bool capturing: false

    onSelectedChanged: capturing = false

    readonly property var item: selected >= 0 && selected < Radial.allItems.length ? Radial.allItems[selected] : null

    readonly property list<MenuItem> typeItems: [
        MenuItem {
            text: Tr.trCtx("Application", "radial action type")
        },
        MenuItem {
            text: Tr.trCtx("Command", "radial action type")
        },
        MenuItem {
            text: Tr.trCtx("Link", "radial action type")
        },
        MenuItem {
            text: Tr.trCtx("Caelestia", "radial action type")
        }
    ]

    readonly property list<MenuItem> anchorItems: [
        MenuItem {
            text: "center"
        },
        MenuItem {
            text: "top"
        },
        MenuItem {
            text: "top-left"
        },
        MenuItem {
            text: "top-right"
        },
        MenuItem {
            text: "left"
        },
        MenuItem {
            text: "right"
        },
        MenuItem {
            text: "bottom-left"
        },
        MenuItem {
            text: "bottom"
        },
        MenuItem {
            text: "bottom-right"
        }
    ]

    function typeKey(type: string): int {
        switch (type) {
        case "command":
            return 1;
        case "url":
            return 2;
        case "caelestia":
            return 3;
        default:
            return 0;
        }
    }

    function typeFromKey(index: int): string {
        return ["app", "command", "url", "caelestia"][index] ?? "app";
    }

    title: Tr.tr("Radial menu")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ---- layout ----
        SectionHeader {
            first: true
            text: Tr.tr("Layout")
        }

        StepperRow {
            first: true
            label: Tr.tr("Radius")
            subtext: Tr.tr("Distance between the centre and the items")
            value: Radial.radius
            from: 60
            to: 280
            stepSize: 5
            onMoved: v => Radial.setMenuValue("radius", v)
        }

        StepperRow {
            label: Tr.tr("Start angle")
            subtext: Tr.tr("Where the first item sits (-90 is the top)")
            value: Radial.startAngle
            from: -180
            to: 180
            stepSize: 15
            onMoved: v => Radial.setMenuValue("startAngle", v)
        }

        SelectRow {
            label: Tr.tr("Position")
            subtext: Tr.tr("Where the menu opens on screen")
            menuItems: root.anchorItems
            active: menuItems.find(i => i.text === Radial.anchor) ?? menuItems[0]
            onSelected: item => Radial.setMenuValue("anchor", item.text)
        }

        ToggleRow {
            text: Tr.tr("Hold to activate")
            subtext: Tr.tr("Hold the shortcut, move to an item, release to run it")
            checked: Radial.holdToActivate
            onToggled: Radial.setMenuValue("holdToActivate", checked)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Test the menu")
            subtext: Tr.tr("Open the radial menu right now")
            onToggled: {
                if (checked)
                    Radial.show("", Radial.holdToActivate);
                else
                    Radial.hide();
                checked = Radial.open;
            }
        }

        // ---- items ----
        SectionHeader {
            text: Tr.tr("Items")
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.largeIncreased
            Layout.rightMargin: Tokens.padding.largeIncreased
            text: Tr.tr("Drag to reorder, use the switch to hide an item, tap it to edit.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        ListEditor {
            id: editor

            values: Radial.allItems
            first: true

            function labelFor(item: var): string {
                const label = item.label ?? "";
                const value = item.value ?? "";
                return value.length > 0 ? `${label} — ${value}` : label;
            }

            function toggledFor(item: var): bool {
                return item.enabled !== false;
            }

            onItemMoved: (from, to) => {
                Radial.moveItem(from, to);
                if (root.selected === from)
                    root.selected = to;
                else if (root.selected === to)
                    root.selected = from;
            }
            onItemRemoved: index => {
                Radial.removeItem(index);
                if (root.selected === index)
                    root.selected = -1;
                else if (root.selected > index)
                    root.selected--;
            }
            onItemToggled: (index, checked) => Radial.setItem(index, "enabled", checked)
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "add"
            text: Tr.tr("Add item")
            type: IconTextButton.Tonal
            onClicked: {
                Radial.addItem();
                root.selected = Radial.allItems.length - 1;
            }
        }

        // ---- item editor ----
        SectionHeader {
            visible: root.item !== null
            text: Tr.tr("Edit item")
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.item !== null
            spacing: Tokens.spacing.extraSmall / 2

            TextFieldRow {
                first: true
                label: Tr.tr("Label")
                subtext: Tr.tr("Shown when hovering the item")
                value: root.item?.label ?? ""
                placeholderText: Tr.tr("Label")
                onValueEdited: value => Radial.setItem(root.selected, "label", value)
            }

            SelectRow {
                label: Tr.tr("Type")
                subtext: Tr.tr("What the item does when activated")
                menuItems: root.typeItems
                active: menuItems[root.typeKey(root.item?.type ?? "app")] ?? menuItems[0]
                onSelected: item => Radial.setItem(root.selected, "type", root.typeFromKey(root.typeItems.indexOf(item)))
            }

            TextFieldRow {
                label: Tr.tr(root.item?.type === "app" ? "Application" : root.item?.type === "url" ? "Link" : root.item?.type === "caelestia" ? "Action" : "Command")
                subtext: {
                    switch (root.item?.type) {
                    case "app":
                        return Tr.tr("Desktop entry id, e.g. firefox or foot");
                    case "url":
                        return Tr.tr("Opened in your default browser");
                    case "caelestia":
                        return Tr.tr("e.g. toggleNightMode, screenshot, record, lockScreen");
                    default:
                        return Tr.tr("Shell command to run");
                    }
                }
                value: root.item?.value ?? ""
                placeholderText: Tr.tr("Value")
                onValueEdited: value => Radial.setItem(root.selected, "value", value)
            }

            TextFieldRow {
                label: Tr.tr("Icon")
                subtext: Tr.tr("Material icon name, leave empty to use the app icon")
                value: root.item?.icon ?? ""
                placeholderText: Tr.tr("terminal")
                onValueEdited: value => Radial.setItem(root.selected, "icon", value)
            }

            ConnectedRect {
                Layout.fillWidth: true

                implicitHeight: keyRow.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: keyRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: Tr.tr("Activation key")
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const dupes = Radial.duplicateKeys();
                                if (dupes.length > 0)
                                    return Tr.tr("Conflict: %1 assigned twice — reassign to resolve").arg(dupes.join(", "));
                                if (root.capturing)
                                    return Tr.tr("Press a key, Backspace clears, Esc cancels");
                                return Tr.tr("Number or letter to trigger this slot");
                            }
                            color: Radial.duplicateKeys().length > 0 ? Colours.palette.m3error : Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    TextButton {
                        id: keyButton

                        Layout.alignment: Qt.AlignVCenter
                        text: root.capturing ? Tr.tr("Press a key…") : (Radial.keyFor(root.item) || Tr.tr("Set key"))
                        font: Tokens.font.label.medium
                        onClicked: {
                            root.capturing = true;
                            keyButton.forceActiveFocus();
                        }
                        onActiveFocusChanged: {
                            if (!activeFocus)
                                root.capturing = false;
                        }

                        Keys.onPressed: event => {
                            if (!root.capturing)
                                return;
                            if (event.key === Qt.Key_Escape) {
                                root.capturing = false;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                                Radial.assignKey(root.selected, "");
                                root.capturing = false;
                                event.accepted = true;
                            } else if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) {
                                // Ignore chords, stay in capture mode.
                            } else {
                                const k = Radial.normaliseKey(event.text);
                                if (k) {
                                    const displaced = Radial.assignKey(root.selected, k);
                                    if (displaced)
                                        Toaster.toast(Tr.tr("Key %1 moved").arg(k), Tr.tr("%1 lost its assignment").arg(displaced), "keyboard");
                                    root.capturing = false;
                                    event.accepted = true;
                                }
                            }
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        visible: Radial.keyFor(root.item) !== ""
                        icon: "close"
                        type: IconButton.Text
                        onClicked: Radial.assignKey(root.selected, "")
                    }
                }
            }
        }

        // Reset
        NavRow {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            last: true
            trailingIcon: ""
            icon: "restart_alt"
            text: Tr.tr("Reset to defaults")
            subtext: Tr.tr("Restore the default radial menu items and layout")
            onClicked: {
                Radial.resetDefaults();
                root.selected = -1;
                Toaster.toast(Tr.tr("Radial menu reset"), Tr.tr("Default items and layout restored"), "restart_alt");
            }
        }
    }
}
