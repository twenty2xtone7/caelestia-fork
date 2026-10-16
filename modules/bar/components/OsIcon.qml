pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property var popouts
    required property var bar

    implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.2)
    implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.2)

    // Opens (or closes) the taskbar-position panel. The anchor is reported in
    // bar coordinates so the popout lands next to the logo on any edge.
    function togglePanel(): void {
        if (root.popouts.hasCurrent && root.popouts.currentName === "barposition") {
            root.popouts.hasCurrent = false;
            return;
        }

        root.popouts.currentName = "barposition";
        root.popouts.currentCenter = BarState.horizontal ? root.mapToItem(root.bar, root.width / 2, 0).x : root.mapToItem(root.bar, 0, root.height / 2).y;
        root.popouts.hasCurrent = true;
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            // Left click opens the layout picker; right click keeps the
            // original launcher toggle available.
            if (event.button === Qt.RightButton) {
                const screenState = ShellState.forActive();
                screenState.launcher = !screenState.launcher;
            } else {
                root.togglePanel();
            }
        }
    }

    Loader {
        asynchronous: true
        anchors.centerIn: parent
        sourceComponent: SysInfo.isDefaultLogo ? caelestiaLogo : distroIcon
    }

    Component {
        id: caelestiaLogo

        Logo {
            implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.6)
            implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.6)
        }
    }

    Component {
        id: distroIcon

        ColouredIcon {
            source: SysInfo.osLogo
            implicitSize: Math.round(Tokens.font.body.large.pointSize * 1.2)
            colour: Colours.palette.m3tertiary
        }
    }
}
