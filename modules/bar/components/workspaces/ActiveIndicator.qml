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
    property bool orientationChanged: false

    function runAnim(): void {
        if (!activeWs)
            return;

        if (!root.horizontal && !activeWs.LazyListView.ready && !orientationChanged)
            return;

        const newStart = root.horizontal ? activeWs.x : activeWs.LazyListView.layoutY;
        const newSize = root.horizontal ? activeWs.width : activeWs.LazyListView.preferredHeight;

        if (orientationChanged) {
            orientationChanged = false;
            startAnim.stop();
            endAnim.stop();
            start = newStart;
            end = newStart + newSize;
            return;
        }

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
    onHorizontalChanged: {
        orientationChanged = true;
        runAnim();
    }
    Component.onCompleted: runAnim()

    clip: true
    x: root.horizontal ? start + mask.x : (activeWs ? activeWs.x : 0)
    y: root.horizontal ? 0 : start + mask.y
    implicitWidth: root.horizontal ? end - start : (activeWs ? activeWs.width : 0)
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

        function onReadyChanged(): void {
            root.runAnim();
        }

        function onTargetChanged(): void {
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

        function onTargetChanged(): void {
            root.runAnim();
        }

        target: root.activeWs ?? null
    }

    Colouriser {
        id: colouriser

        source: root.mask
        sourceColor: Colours.palette.m3onSurface
        colorizationColor: Colours.palette.m3onPrimary

        x: root.horizontal ? -parent.start : -parent.x
        y: root.horizontal ? 0 : -parent.start
        implicitWidth: root.mask.width
        implicitHeight: root.mask.height
    }
}
