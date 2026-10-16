pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

StyledRect {
    id: root

    required property Workspace activeWs
    required property Item mask
    property bool horizontal: false
    property alias contentColour: colouriser.colorizationColor

    property real start
    property real end

    function runAnim(): void {
        if (!activeWs)
            return;

        const newStart = root.horizontal ? activeWs.x : activeWs.LazyListView.layoutY;
        const newSize = root.horizontal ? activeWs.width : activeWs.LazyListView.preferredHeight;
        const goingUp = newStart < start;
        const leadingDuration = Tokens.anim.durations.expressiveDefaultSpatial;
        const trailingDuration = leadingDuration * (Config.bar.workspaces.activeTrail ? 1.5 : 1);

        startAnim.stop();
        endAnim.stop();
        startAnim.to = newStart;
        endAnim.to = newStart + newSize;
        startAnim.duration = goingUp ? leadingDuration : trailingDuration;
        endAnim.duration = goingUp ? trailingDuration : leadingDuration;
        startAnim.start();
        endAnim.start();
    }

    onActiveWsChanged: runAnim()
    Component.onCompleted: runAnim()

    clip: true
    x: root.horizontal ? start + mask.x : 0
    y: root.horizontal ? 0 : start + mask.y
    implicitWidth: root.horizontal ? end - start : 0
    implicitHeight: root.horizontal ? mask.height : end - start
    radius: Tokens.rounding.full
    color: Colours.palette.m3primary

    Anim on start {
        id: startAnim
    }

    Anim on end {
        id: endAnim
    }

    Connections {
        enabled: !root.horizontal
        function onLayoutYChanged(): void {
            root.runAnim();
        }

        function onPreferredHeightChanged(): void {
            root.runAnim();
        }

        target: root.activeWs?.LazyListView ?? null
    }

    Connections {
        enabled: root.horizontal
        function onXChanged(): void {
            root.runAnim();
        }

        function onWidthChanged(): void {
            root.runAnim();
        }

        target: root.activeWs ?? null
    }

    Colouriser {
        id: colouriser

        source: root.mask
        sourceColor: Colours.palette.m3onSurface
        colorizationColor: Colours.palette.m3onPrimary

        x: root.horizontal ? -parent.start : 0
        y: root.horizontal ? 0 : -parent.start
        implicitWidth: root.mask.width
        implicitHeight: root.mask.height

        anchors.horizontalCenter: root.horizontal ? undefined : parent.horizontalCenter
        anchors.verticalCenter: root.horizontal ? parent.verticalCenter : undefined
    }
}
