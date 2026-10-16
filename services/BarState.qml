pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.utils

// Global taskbar position state. Caelestia's bar has no native concept of
// position, so this is the single source of truth the whole shell reads to
// decide which edge the bar occupies and, therefore, which axis everything
// attached to it lays out along.
Singleton {
    id: root

    // "top" | "bottom" | "left" | "right"
    property string position: "left"

    readonly property var positions: ["top", "bottom", "left", "right"]

    // `horizontal` bars span the screen width (top/bottom); `vertical` bars
    // span the height (left/right).
    readonly property bool horizontal: position === "top" || position === "bottom"
    readonly property bool vertical: !horizontal

    // Which extreme of the cross axis the bar sits against. `atStart` is the
    // left/top edge, `atEnd` the right/bottom edge.
    readonly property bool atStart: position === "left" || position === "top"
    readonly property bool atEnd: !atStart

    // ---- Panel placement ---------------------------------------------------
    // Where the shell's edge-anchored panels (volume OSD, sidebar) sit for the
    // current bar edge, so every consumer agrees on one set of rules:
    //   - a right-edge bar leaves no room on the right, so the OSD flips to
    //     the left edge (vertically centred) and the sidebar moves to the
    //     bottom-left, growing upwards;
    //   - a bottom-edge bar keeps the OSD on the right, but hangs the sidebar
    //     from the top-left so it opens downwards and never reaches the bar;
    //   - the other layouts are the upstream default and stay untouched.
    readonly property bool barOnRight: vertical && atEnd
    readonly property bool barOnBottom: horizontal && atEnd
    readonly property bool osdOnLeft: barOnRight
    readonly property bool sidebarOnLeft: barOnRight || barOnBottom
    readonly property bool sidebarFromTop: barOnBottom
    readonly property bool sidebarFromBottom: barOnRight

    function setPosition(p: string): void {
        if (positions.indexOf(p) === -1 || p === root.position)
            return;

        // Retract the bar first, then switch edges and let it extend again, so
        // the layout change reads as one motion instead of an instant jump.
        root.pendingPosition = p;
        root.transitioning = true;
        settleTimer.restart();
    }

    // Edge currently being animated towards; empty when idle.
    property string pendingPosition: ""
    property bool transitioning: false

    Timer { // ponytail: ~one bar collapse; wire to Tokens.anim if it ever moves
        id: settleTimer

        interval: 180
        onTriggered: {
            root.position = root.pendingPosition;
            root.pendingPosition = "";
            root.transitioning = false;
        }
    }

    function displayName(p: string): string {
        return p.charAt(0).toUpperCase() + p.slice(1);
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/bar-position.txt`
        onLoaded: {
            const saved = text().trim();
            if (root.positions.indexOf(saved) !== -1)
                root.position = saved;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                Qt.callLater(() => setText(root.position));
        }
    }

    onPositionChanged: storage.setText(root.position)
}
