pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.utils
import qs.modules.bar.popouts // Need to import this module so the Wrapper type is the same as others

// Positions a bar popout next to the bar on whichever edge it currently sits,
// animated out of / back into the bar. For a left bar this is unchanged.
Item {
    id: root

    required property ShellScreen screen
    required property real borderThickness

    readonly property alias content: content
    property real offsetScale: content.hasCurrent || content.isDetached ? 0 : 1

    visible: width > 0 && height > 0
    clip: true

    implicitWidth: BarState.horizontal ? content.implicitWidth : content.implicitWidth * (1 - offsetScale)
    implicitHeight: BarState.horizontal ? content.implicitHeight * (1 - offsetScale) : content.implicitHeight

    x: {
        if (content.isDetached)
            return (parent.width - content.nonAnimWidth) / 2;

        if (BarState.horizontal) {
            const off = content.currentCenter - borderThickness - content.nonAnimWidth / 2;
            const diff = parent.width - Math.floor(off + content.nonAnimWidth);
            return diff < 0 ? off + diff : Math.max(off, 0);
        }

        return BarState.atStart ? 0 : parent.width - content.nonAnimWidth;
    }

    y: {
        if (content.isDetached)
            return (parent.height - content.nonAnimHeight) / 2;

        if (!BarState.horizontal) {
            const off = content.currentCenter - borderThickness - content.nonAnimHeight / 2;
            const diff = parent.height - Math.floor(off + content.nonAnimHeight);
            if (diff < 0)
                return off + diff;
            return Math.max(off, 0);
        }

        return BarState.atStart ? 0 : parent.height - content.nonAnimHeight;
    }

    Behavior on offsetScale {
        Anim {}
    }

    // The bar's own axis animates the alignment; the other axis is the slide.
    Behavior on x {
        enabled: BarState.horizontal && root.offsetScale < 1

        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Behavior on y {
        enabled: BarState.vertical && root.offsetScale < 1

        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Wrapper {
        id: content

        screen: root.screen
        offsetScale: root.offsetScale

        // Slides back into the bar when hidden, from whichever edge it lives on.
        x: (BarState.horizontal ? 0 : (BarState.atStart ? -1 : 1) * (implicitWidth + 5)) * root.offsetScale
        y: (BarState.horizontal ? (BarState.atStart ? -1 : 1) * (implicitHeight + 5) : 0) * root.offsetScale
    }
}
