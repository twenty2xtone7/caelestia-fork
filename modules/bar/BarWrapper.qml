pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen

    readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)

    // Cross-axis thickness of the bar. Identical for every edge, which is why
    // widgets only ever need swapping along one axis.
    readonly property int clampedThickness: Math.max(Config.border.minThickness, BarState.vertical ? implicitWidth : implicitHeight)
    readonly property int padding: Math.max(Tokens.padding.small, Config.border.thickness)
    readonly property int contentWidth: Tokens.sizes.bar.innerWidth + padding * 2
    readonly property int exclusiveZone: !disabled && (Config.bar.persistent || screenState.bar) ? contentWidth : Config.border.thickness
    readonly property bool shouldBeVisible: !fullscreen && !disabled && (Config.bar.persistent || screenState.bar || isHovered)
    property bool isHovered

    // How far the bar pushes the rest of the shell inward, along each axis.
    // A vertical bar insets horizontally; a horizontal bar insets vertically.
    readonly property real insetX: BarState.vertical ? implicitWidth : 0
    readonly property real insetY: BarState.horizontal ? implicitHeight : 0

    readonly property real borderThickness: Config.border.thickness

    // Offset of the panel container (Panels) from the window origin. Panels
    // only gain a margin on the edge the bar occupies; the other edges keep
    // the normal border thickness.
    readonly property real panelsOffsetX: BarState.vertical && BarState.atStart ? implicitWidth : borderThickness
    readonly property real panelsOffsetY: BarState.horizontal && BarState.atStart ? implicitHeight : borderThickness

    // Legacy alias used by the mask regions; the bar's cross-axis extent.
    readonly property int clampedWidth: clampedThickness
    readonly property int clampedHeight: clampedThickness

    // True when the given point (in root/screen coordinates) is over the bar
    // strip. Widgets and panels use this instead of hard-coding the left edge.
    function withinBar(x: real, y: real): bool {
        if (BarState.vertical)
            return BarState.atStart ? x < clampedThickness : x >= width - clampedThickness;
        return BarState.atStart ? y < clampedThickness : y >= height - clampedThickness;
    }

    function closeTray(): void {
        (content.item as Bar)?.closeTray();
    }

    function checkPopout(x: real, y: real): void {
        (content.item as Bar)?.checkPopout(x, y);
    }

    function handleWheel(x: real, y: real, angleDelta: point): void {
        (content.item as Bar)?.handleWheel(x, y, angleDelta);
    }

    clip: true
    visible: (BarState.vertical ? width : height) > Config.border.thickness

    // No anchors: the strip is positioned manually so it can sit on any edge.
    width: BarState.horizontal ? parent.width : implicitWidth
    height: BarState.vertical ? parent.height : implicitHeight

    x: BarState.vertical && BarState.atEnd ? parent.width - width : 0
    y: BarState.horizontal && BarState.atEnd ? parent.height - height : 0

    implicitWidth: fullscreen || BarState.horizontal ? 0 : Config.border.thickness
    implicitHeight: fullscreen || BarState.vertical ? 0 : Config.border.thickness

    states: State {
        // `transitioning` gates the visible state so the bar collapses into its
        // edge while the position is being swapped, then extends out of the
        // new edge — reusing the existing show/hide animations.
        name: "visible"
        when: root.shouldBeVisible && !BarState.transitioning

        PropertyChanges {
            root.implicitWidth: BarState.vertical ? root.contentWidth : 0
            root.implicitHeight: BarState.horizontal ? root.contentWidth : 0
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                property: "implicitWidth"
            }

            Anim {
                target: root
                property: "implicitHeight"
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                property: "implicitWidth"
                type: Anim.Emphasized
            }

            Anim {
                target: root
                property: "implicitHeight"
                type: Anim.Emphasized
            }
        }
    ]

    Loader {
        id: content

        active: root.shouldBeVisible

        width: BarState.horizontal ? parent.width : root.contentWidth
        height: BarState.vertical ? parent.height : root.contentWidth
        x: BarState.vertical && BarState.atStart ? parent.width - width : 0
        y: BarState.horizontal && BarState.atStart ? parent.height - height : 0

        opacity: BarState.transitioning ? 0 : 1

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        sourceComponent: Bar {
            screen: root.screen
            screenState: root.screenState
            popouts: root.popouts // qmllint disable incompatible-type
            fullscreen: root.fullscreen
        }
    }
}
