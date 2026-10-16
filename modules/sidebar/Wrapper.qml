pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import qs.components

Item {
    id: root

    required property ScreenState screenState
    readonly property Props props: Props {}

    readonly property bool shouldBeActive: screenState.sidebar && Config.sidebar.enabled
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    // Distance the drawer sits off its edge while hidden. Exposed so the host
    // (drawers/Panels.qml) can apply it to whichever edge the sidebar is
    // anchored to, using the same offsetScale animation either way.
    readonly property real slideOffset: (-implicitWidth - 5) * offsetScale
    // Same idea for the placements that reveal the drawer from the top or
    // bottom edge (bottom/right taskbar), which travel a full column height.
    readonly property real slideOffsetVertical: (-height - 5) * offsetScale
    anchors.rightMargin: root.slideOffset
    implicitWidth: Tokens.sizes.sidebar.width
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.large
        anchors.margins: CUtils.clamp(anchors.leftMargin - Config.border.thickness, 0, anchors.leftMargin)
        anchors.bottomMargin: 0

        asynchronous: false
        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            implicitWidth: Tokens.sizes.sidebar.width - content.anchors.leftMargin - content.anchors.margins
            props: root.props
            screenState: root.screenState
        }
    }
}
