pragma ComponentBehavior: Bound

import "popouts" as BarPopouts
import "components"
import "components/workspaces"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

// The bar is a single row or column depending on the taskbar position. A
// GridLayout lays out along one axis when `columns`/`rows` is fixed to 1, so
// the entry list below is written once and works on every edge.
GridLayout {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    readonly property bool horizontal: BarState.horizontal
    readonly property int vPadding: Tokens.padding.large
    readonly property int spacing: Tokens.spacing.medium

    columns: horizontal ? -1 : 1
    rows: horizontal ? 1 : -1

    function closeTray(): void {
        if (!Config.bar.tray.compact)
            return;

        for (let i = 0; i < repeater.count; i++) {
            const tray = (repeater.itemAt(i) as EntryWrapper)?.item as Tray;
            if (tray)
                tray.expanded = false;
        }
    }

    // Locates the bar entry under (x, y) and reports the tooltip/popout anchor
    // for the hovered child. The along-axis coordinate is `x` for horizontal
    // bars and `y` for vertical ones.
    function checkPopout(x: real, y: real): void {
        const ch = (root.horizontal ? childAt(x, height / 2) : childAt(width / 2, y)) as EntryWrapper;

        if (ch?.entryId !== "tray")
            closeTray();

        if (!ch) {
            if (popouts.currentName !== "barposition")
                popouts.hasCurrent = false;
            return;
        }

        const id = ch.entryId;
        const start = root.horizontal ? ch.x : ch.y;
        const pos = root.horizontal ? x : y;

        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            const items = (ch.item as StatusIcons).items;
            const icon = root.horizontal ? items.childAt(mapToItem(items, x, 0).x, items.height / 2) : items.childAt(items.width / 2, mapToItem(items, 0, y).y);
            if (icon) {
                popouts.currentName = icon.name;
                popouts.currentCenter = Qt.binding(() => root.horizontal ? icon.mapToItem(root, icon.implicitWidth / 2, 0).x : icon.mapToItem(root, 0, icon.implicitHeight / 2).y);
                popouts.hasCurrent = true;
            }
        } else if (id === "tray" && Config.bar.popouts.tray) {
            const tray = ch.item as Tray;
            const onExpand = root.horizontal ? tray.expandIcon.contains(mapToItem(tray.expandIcon, x, tray.implicitHeight / 2)) : tray.expandIcon.contains(mapToItem(tray.expandIcon, tray.implicitWidth / 2, y));
            if (!Config.bar.tray.compact || (tray.expanded && !onExpand)) {
                const trayLength = root.horizontal ? tray.layout.implicitWidth : tray.layout.implicitHeight;
                const index = Math.floor(((pos - start - tray.padding * 2 + tray.spacing) / trayLength) * tray.items.count);
                const trayItem = tray.items.itemAt(index);
                if (trayItem) {
                    popouts.currentName = `traymenu${index}`;
                    popouts.currentCenter = Qt.binding(() => root.horizontal ? trayItem.mapToItem(root, trayItem.implicitWidth / 2, 0).x : trayItem.mapToItem(root, 0, trayItem.implicitHeight / 2).y);
                    popouts.hasCurrent = true;
                } else {
                    popouts.hasCurrent = false;
                }
            } else {
                popouts.hasCurrent = false;
                tray.expanded = true;
            }
        } else if (id === "activeWindow" && Config.bar.popouts.activeWindow && Config.bar.activeWindow.showOnHover) {
            popouts.currentName = id.toLowerCase();
            popouts.currentCenter = root.horizontal ? (ch.item as Item).mapToItem(root, (ch.item as Item).implicitWidth / 2, 0).x : (ch.item as Item).mapToItem(root, 0, (ch.item as Item).implicitHeight / 2).y ?? 0;
            popouts.hasCurrent = true;
        }
    }

    function handleWheel(x: real, y: real, angleDelta: point): void {
        const ch = (root.horizontal ? childAt(x, height / 2) : childAt(width / 2, y)) as EntryWrapper;
        if (ch?.entryId === "workspaces" && Config.bar.scrollActions.workspaces) {
            // Workspace scroll
            const mon = Hypr.monitorFor(screen);
            const specialWs = mon?.lastIpcObject.specialWorkspace.name;
            if (specialWs?.length > 0)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${specialWs.slice(8)}")` : `togglespecialworkspace ${specialWs.slice(8)}`);
            else if (angleDelta.y < 0 || mon.activeWorkspace?.id > 1)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "r${angleDelta.y > 0 ? "-" : "+"}1" })` : `workspace r${angleDelta.y > 0 ? "-" : "+"}1`);
        } else if ((root.horizontal ? x < screen.width / 2 : y < screen.height / 2) && Config.bar.scrollActions.volume) {
            // Volume scroll on the leading half
            if (angleDelta.y > 0)
                Audio.incrementVolume();
            else if (angleDelta.y < 0)
                Audio.decrementVolume();
        } else if (Config.bar.scrollActions.brightness) {
            // Brightness scroll on the trailing half
            const monitor = Brightness.getMonitorForScreen(screen);
            if (angleDelta.y > 0)
                monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
            else
                monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
        }
    }

    rowSpacing: root.spacing
    columnSpacing: root.spacing

    Repeater {
        id: repeater

        model: ScriptModel {
            values: root.Config.bar.entries.values.filter(e => e.enabled)
        }

        DelegateChooser {
            role: "id"

            DelegateChoice {
                roleValue: "spacer"
                delegate: EntryWrapper {
                    Layout.fillHeight: !root.horizontal
                    Layout.fillWidth: root.horizontal
                }
            }
            DelegateChoice {
                roleValue: "logo"
                delegate: EntryWrapper {
                    OsIcon {
                        objectName: "taskbarLogo"
                        popouts: root.popouts
                        bar: root
                    }
                }
            }
            DelegateChoice {
                roleValue: "workspaces"
                delegate: EntryWrapper {
                    Workspaces {
                        objectName: "taskbarWorkspaces"
                        screen: root.screen
                        fullscreen: root.fullscreen
                    }
                }
            }
            DelegateChoice {
                roleValue: "activeWindow"
                delegate: EntryWrapper {
                    ActiveWindow {
                        objectName: "taskbarActiveWindow"
                        bar: root
                        monitor: Brightness.getMonitorForScreen(root.screen)
                    }
                }
            }
            DelegateChoice {
                roleValue: "tray"
                delegate: EntryWrapper {
                    Tray {
                        objectName: "taskbarTray"
                    }
                }
            }
            DelegateChoice {
                roleValue: "clock"
                delegate: EntryWrapper {
                    Clock {
                        objectName: "taskbarClock"
                    }
                }
            }
            DelegateChoice {
                roleValue: "statusIcons"
                delegate: EntryWrapper {
                    StatusIcons {
                        objectName: "taskbarStatusIcons"
                    }
                }
            }
            DelegateChoice {
                roleValue: "power"
                delegate: EntryWrapper {
                    Power {
                        objectName: "taskbarPowerButton"
                        screenState: root.screenState
                    }
                }
            }
        }
    }

    component EntryWrapper: Item {
        required property var modelData
        required property int index
        default property Item item
        readonly property string entryId: modelData.id

        Layout.topMargin: !root.horizontal && index === 0 ? root.vPadding : 0
        Layout.bottomMargin: !root.horizontal && index === repeater.count - 1 ? root.vPadding : 0
        Layout.leftMargin: root.horizontal && index === 0 ? root.vPadding : 0
        Layout.rightMargin: root.horizontal && index === repeater.count - 1 ? root.vPadding : 0
        Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item
    }
}
