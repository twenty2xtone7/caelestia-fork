pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.bar as Bar
import qs.modules.dashboard as Dashboard
import qs.modules.launcher as Launcher
import qs.modules.notifications as Notifications
import qs.modules.osd as Osd
import qs.modules.session as Session
import qs.modules.sidebar as Sidebar
import qs.modules.utilities as Utilities
import qs.modules.bar.popouts as BarPopouts
import qs.modules.utilities.toasts as Toasts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property Bar.BarWrapper bar
    required property real borderThickness

    readonly property alias osd: osd
    readonly property alias osdWrapper: osdWrapper
    readonly property alias notifications: notifications
    readonly property alias session: session
    readonly property alias sessionWrapper: sessionWrapper
    readonly property alias launcher: launcher
    readonly property alias dashboard: dashboard
    readonly property alias popouts: popoutsWrapper.content
    readonly property alias popoutsWrapper: popoutsWrapper
    readonly property alias utilities: utilities
    readonly property alias toasts: toasts
    readonly property alias sidebar: sidebar

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.leftMargin: BarState.vertical && BarState.atStart ? bar.implicitWidth : borderThickness
    anchors.rightMargin: BarState.vertical && BarState.atEnd ? bar.implicitWidth : borderThickness
    anchors.topMargin: BarState.horizontal && BarState.atStart ? bar.implicitHeight : borderThickness
    anchors.bottomMargin: BarState.horizontal && BarState.atEnd ? bar.implicitHeight : borderThickness

    Item {
        id: osdWrapper

        // Mirrored horizontally when the taskbar owns the right edge; the
        // vertical placement (screen centre) is the same on every layout.
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: BarState.osdOnLeft ? parent.left : undefined
        anchors.right: BarState.osdOnLeft ? undefined : parent.right
        anchors.rightMargin: BarState.osdOnLeft ? 0 : sessionWrapper.anchors.rightMargin + session.width * (1 - session.offsetScale)
        clip: sidebar.visible || session.visible

        implicitWidth: osd.implicitWidth * (1 - osd.offsetScale)
        implicitHeight: osd.implicitHeight

        Osd.Wrapper {
            id: osd

            screen: root.screen
            screenState: root.screenState
            sidebarOrSessionVisible: sidebar.visible || session.visible

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: BarState.osdOnLeft ? parent.left : undefined
            anchors.leftMargin: BarState.osdOnLeft ? osd.slideOffset : 0
            anchors.right: BarState.osdOnLeft ? undefined : parent.right
        }
    }

    Notifications.Wrapper {
        id: notifications

        screenState: root.screenState
        sidebarPanel: sidebar
        osdPanel: osdWrapper
        sessionPanel: sessionWrapper
        utilitiesPanel: utilities

        anchors.top: parent.top
        anchors.right: parent.right
    }

    Item {
        id: sessionWrapper

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sidebar.width * (1 - sidebar.offsetScale)
        clip: sidebar.visible

        implicitWidth: session.implicitWidth * (1 - session.offsetScale)
        implicitHeight: session.implicitHeight

        Session.Wrapper {
            id: session

            screenState: root.screenState
            sidebarVisible: sidebar.visible

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Launcher.Wrapper {
        id: launcher

        screen: root.screen
        screenState: root.screenState
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }

    Dashboard.Wrapper {
        id: dashboard

        screenState: root.screenState

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    BarPopouts.ClipWrapper {
        id: popoutsWrapper

        screen: root.screen
        borderThickness: root.borderThickness
    }

    Utilities.Wrapper {
        id: utilities

        screenState: root.screenState
        sidebar: sidebar
        popouts: popoutsWrapper.content

        anchors.bottom: parent.bottom
        anchors.right: parent.right
    }

    Toasts.Toasts {
        id: toasts

        // Upstream pins toasts to `sidebar.left`, which is the screen's right
        // edge whenever the sidebar is one of the right-side panels. Only when
        // the sidebar itself sits on the left edge (bar bottom/right) do the
        // toasts need to hang off the utilities card instead.
        anchors.bottom: BarState.sidebarOnLeft ? utilities.top : (sidebar.visible ? parent.bottom : utilities.top)
        anchors.right: BarState.sidebarOnLeft ? utilities.left : sidebar.left
        anchors.margins: Tokens.padding.medium
    }

    Sidebar.Wrapper {
        id: sidebar

        screenState: root.screenState

        // The sidebar keeps its upstream position (right edge, hanging
        // between the notifications and the utilities) for a left or top
        // taskbar. A bottom taskbar parks it on the left, flush with the top
        // so it opens downwards; a right taskbar parks it on the left flush
        // with the bottom so it opens upwards. Either way it sits on the edge
        // the bar does not occupy, so it can never overlap the bar.
        anchors.left: BarState.sidebarOnLeft ? parent.left : undefined
        anchors.right: BarState.sidebarOnLeft ? undefined : parent.right

        // Left placements span the full column and hang from a single edge,
        // so the reveal animates that one margin without resizing the drawer.
        anchors.top: BarState.sidebarOnLeft ? (BarState.sidebarFromTop ? parent.top : undefined) : notifications.bottom
        anchors.bottom: BarState.sidebarOnLeft ? (BarState.sidebarFromBottom ? parent.bottom : undefined) : utilities.top
        anchors.topMargin: BarState.sidebarFromTop ? sidebar.slideOffsetVertical : (BarState.sidebarOnLeft ? 0 : -notifications.anchors.topMargin)
        anchors.bottomMargin: BarState.sidebarFromBottom ? sidebar.slideOffsetVertical : 0
        height: BarState.sidebarOnLeft ? parent.height : implicitHeight

        // Expand-all grows the dock to fill the column down to
        // bottomMargin (currently 10%, so ~90% tall) while utilities
        // squeezes into the remaining strip and scrolls internally, so
        // every card stays reachable. Collapsing hands the space back.
        // Scoped to expand-all only; single groups expand in place.
        states: State {
            name: "tall"
            when: sidebar.props.dockTall

            AnchorChanges {
                target: sidebar
                anchors.bottom: parent.bottom
            }
            PropertyChanges {
                target: sidebar
                anchors.bottomMargin: Math.round(parent.height * 0.1)
            }
            PropertyChanges {
                target: utilities
                height: Math.round(parent.height * 0.1)
            }
        }

        // Expand-all writes an explicit height. Restore the card-following
        // bind on collapse, or the panel stays frozen at 10%.
        Connections {
            target: sidebar.props
            function onDockTallChanged(): void {
                if (!sidebar.props.dockTall)
                    utilities.height = Qt.binding(() => utilities.implicitHeight);
            }
        }

        transitions: Transition {
            AnchorAnimation {
                duration: Tokens.anim.durations.normal
                easing: Tokens.anim.emphasized
            }
            NumberAnimation {
                target: utilities
                property: "height"
                duration: Tokens.anim.durations.normal
                easing: Tokens.anim.emphasized
            }
        }
    }
}
