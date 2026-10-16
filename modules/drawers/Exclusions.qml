pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components.containers
import qs.services
import qs.modules.bar as Bar

Scope {
    id: root

    required property ShellScreen screen
    required property Bar.BarWrapper bar

    ExclusionZone {
        anchors.left: true
        exclusiveZone: BarState.vertical && BarState.atStart ? root.bar.exclusiveZone : Config.border.thickness
    }

    ExclusionZone {
        anchors.top: true
        exclusiveZone: BarState.horizontal && BarState.atStart ? root.bar.exclusiveZone : Config.border.thickness
    }

    ExclusionZone {
        anchors.right: true
        exclusiveZone: BarState.vertical && BarState.atEnd ? root.bar.exclusiveZone : Config.border.thickness
    }

    ExclusionZone {
        anchors.bottom: true
        exclusiveZone: BarState.horizontal && BarState.atEnd ? root.bar.exclusiveZone : Config.border.thickness
    }

    component ExclusionZone: StyledWindow {
        screen: root.screen
        name: "border-exclusion"
        exclusiveZone: contentItem.Config.border.thickness
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
    }
}
