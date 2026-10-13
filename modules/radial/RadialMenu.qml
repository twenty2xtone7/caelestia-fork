pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Full-screen radial menu overlay. Only exists on screen while open, so it
// does no work when closed.
Variants {
    id: root

    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        screen: modelData
        name: "radial"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        // Modal input while open: keys go to this surface only, so an
        // activation keypress can never leak into the app behind the menu.
        // Drops back to None on close, restoring normal input.
        WlrLayershell.keyboardFocus: Radial.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible)
                keyForwarder.forceActiveFocus();
        }

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        visible: Radial.open && (Radial.screenName === "" || Radial.screenName === modelData.name)

        readonly property real itemSize: Tokens.padding.extraLargeIncreased * 2
        readonly property real edgePadding: Tokens.padding.extraLarge

        // Menu origin, derived from the configured anchor
        readonly property point origin: {
            const w = modelData.width;
            const h = modelData.height;
            const m = edgePadding + itemSize / 2;
            switch (Radial.anchor) {
            case "top-left":
                return Qt.point(m, m);
            case "top":
                return Qt.point(w / 2, m);
            case "top-right":
                return Qt.point(w - m, m);
            case "left":
                return Qt.point(m, h / 2);
            case "right":
                return Qt.point(w - m, h / 2);
            case "bottom-left":
                return Qt.point(m, h - m);
            case "bottom":
                return Qt.point(w / 2, h - m);
            case "bottom-right":
                return Qt.point(w - m, h - m);
            default:
                return Qt.point(w / 2, h / 2);
            }
        }

        // Global radius cap, so a huge radius can never throw items away.
        // Individual items are then clamped into the screen below, which keeps
        // the fan shape intact when the menu is anchored near an edge/corner.
        readonly property real radius: {
            const w = modelData.width;
            const h = modelData.height;
            const maxR = Math.min(w, h) / 2 - itemSize - edgePadding;
            return Math.max(0, Math.min(Radial.radius, maxR));
        }

        // Keep a slot fully on screen by nudging its offset inwards
        function clampOffset(offset: point): point {
            const w = modelData.width;
            const h = modelData.height;
            const half = itemSize / 2;
            const minX = edgePadding + half;
            const maxX = w - edgePadding - half;
            const minY = edgePadding + half;
            const maxY = h - edgePadding - half;

            const ax = origin.x + offset.x;
            const ay = origin.y + offset.y;
            return Qt.point(
                offset.x + (maxX - minX < 0 ? 0 : Math.max(minX - ax, Math.min(maxX - ax, 0))),
                offset.y + (maxY - minY < 0 ? 0 : Math.max(minY - ay, Math.min(maxY - ay, 0)))
            );
        }

        // No scrim: the radial floats over the current view without dimming,
        // and clicks outside the menu still close it via the MouseArea below.

        // Keyboard activation: event-driven, only alive while the menu is
        // open. Matched keys are consumed (accepted); everything else passes
        // through unaccepted and behaves as before.
        Item {
            id: keyForwarder

            anchors.fill: parent
            focus: Radial.open

            Keys.onPressed: event => {
                if (!Radial.open)
                    return;
                if (event.key === Qt.Key_Escape) {
                    Radial.hide();
                    event.accepted = true;
                    return;
                }
                // Leave chords to the system; Shift is fine (it shapes text).
                if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier))
                    return;
                const text = event.text ?? "";
                if (text.length === 1 && Radial.activateKey(text))
                    event.accepted = true;
            }
        }

        // Catches clicks outside the menu and tracks the pointer for
        // direction-based selection.
        MouseArea {
            id: input

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons

            onClicked: Radial.hide()
            onExited: Radial.selectedIndex = -1
            onPositionChanged: {
                const dx = mouseX - win.origin.x;
                const dy = mouseY - win.origin.y;
                const dist = Math.hypot(dx, dy);
                const count = Radial.items.length;
                if (dist < win.itemSize * 0.6 || count === 0) {
                    Radial.selectedIndex = -1;
                    return;
                }
                let angle = Math.atan2(dy, dx) * 180 / Math.PI - Radial.startAngle;
                const step = 360 / count;
                angle = ((Math.round(angle / step) * step) % 360 + 360) % 360;
                Radial.selectedIndex = Math.min(count - 1, Math.round(angle / step));
            }
        }

        // Items and centre button live in a container anchored at the origin
        Item {
            id: hub

            x: win.origin.x
            y: win.origin.y
            width: 1
            height: 1

            Repeater {
                model: Radial.items

                delegate: Slot {
                    required property var modelData

                    itemData: modelData
                    count: Radial.items.length
                    radius: win.radius
                    clampOffset: win.clampOffset
                    selected: Radial.selectedIndex === index
                    expanded: Radial.selectedIndex === index
                }
            }

            // Centre button: closes, or runs a configured action
            StyledRect {
                id: centre

                width: win.itemSize * 0.62
                height: win.itemSize * 0.62
                x: -width / 2
                y: -height / 2
                scale: Radial.open ? 1 : 0.3
                opacity: Radial.open ? 1 : 0

                radius: Tokens.rounding.full
                color: Colours.palette.m3primary

                Behavior on scale {
                    Anim {
                        type: Anim.Emphasized
                    }
                }
                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: Radial.centerAction === "close" ? "close" : "auto_awesome"
                    color: Colours.palette.m3onPrimary
                    fontStyle: Tokens.font.icon.large

                    RotationAnimation on rotation {
                        from: -90
                        to: 0
                        duration: Tokens.anim.durations.normal
                        easing.type: Easing.OutCubic
                        running: Radial.open
                    }
                }

                StateLayer {
                    radius: parent.radius
                    color: Colours.palette.m3onPrimary
                    onClicked: Radial.activateCenter()
                }
            }
        }
    }
}
