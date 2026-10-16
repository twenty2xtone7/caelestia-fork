pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.services
import qs.modules.bar as Bar

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win

    readonly property real borderThickness: win.contentItem.Config.border.thickness
    readonly property real clampedThickness: win.contentItem.Config.border.clampedThickness

    // Insets of the interactive region: the bar edge uses the bar's thickness,
    // every other edge the normal border thickness.
    readonly property real insetLeft: BarState.vertical && BarState.atStart ? bar.clampedThickness : clampedThickness
    readonly property real insetRight: BarState.vertical && BarState.atEnd ? bar.clampedThickness : clampedThickness
    readonly property real insetTop: BarState.horizontal && BarState.atStart ? bar.clampedThickness : clampedThickness
    readonly property real insetBottom: BarState.horizontal && BarState.atEnd ? bar.clampedThickness : clampedThickness

    x: insetLeft + win.dragMaskPadding
    y: insetTop + win.dragMaskPadding
    width: win.width - insetLeft - insetRight - win.dragMaskPadding * 2
    height: win.height - insetTop - insetBottom - win.dragMaskPadding * 2
    intersection: Intersection.Xor

    R {
        panel: root.panels.dashboard
        y: 0
        height: panel.height * (1 - root.panels.dashboard.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.launcher
        y: root.win.height - height
        height: panel.height * (1 - root.panels.launcher.offsetScale) + root.borderThickness
    }

    R {
        id: sessionRegion

        panel: root.panels.sessionWrapper
        x: root.win.width - width
        width: panel.width * (1 - root.panels.session.offsetScale) + root.borderThickness + (BarState.sidebarOnLeft ? 0 : sidebarRegion.width)
    }

    R {
        id: sidebarRegion

        panel: root.panels.sidebar
        x: BarState.sidebarOnLeft ? 0 : root.win.width - width
        width: panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.osdWrapper
        x: BarState.osdOnLeft ? 0 : root.win.width - width
        width: panel.width * (1 - root.panels.osd.offsetScale) + root.borderThickness + (BarState.osdOnLeft ? 0 : sessionRegion.width)
    }

    R {
        panel: root.panels.notifications
        y: 0
        height: panel.height + root.borderThickness
    }

    R {
        panel: root.panels.utilities
        y: root.win.height - height
        height: panel.height * (1 - root.panels.utilities.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.popoutsWrapper
        width: panel.width * (1 - root.panels.popoutsWrapper.offsetScale)
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.bar.panelsOffsetX
        y: panel.y + root.bar.panelsOffsetY
        width: panel.width
        height: panel.height
        intersection: Intersection.Subtract
    }
}
