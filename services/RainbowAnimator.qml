pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config

Item {
    id: root

    // Rainbow animation state
    property bool enabled: false
    property real animationSpeed: 1.0 // multiplier, 1.0 = default speed
    property real currentHue: 0 // 0-360
    property real hueOffset: 0 // user-configurable offset
    property real saturation: 1.0 // 0-1 multiplier
    property real brightness: 1.0 // 0-1 multiplier

    readonly property real hue: (currentHue + hueOffset + 360) % 360

    // Accents stay vivid. Surfaces use the same hue at low saturation so the
    // whole scheme shifts together without random unrelated colours.
    readonly property color primary: hsl(hue, 62 * saturation, 74 * brightness)
    readonly property color secondary: hsl((hue + 28) % 360, 38 * saturation, 74 * brightness)
    readonly property color tertiary: hsl((hue + 58) % 360, 52 * saturation, 72 * brightness)
    readonly property color error: hsl((hue + 140) % 360, 72 * saturation, 68 * brightness)

    readonly property color surface: hsl(hue, 18 * saturation, 8 * brightness)
    readonly property color surfaceContainer: hsl(hue, 16 * saturation, 14 * brightness)
    readonly property color surfaceContainerHigh: hsl(hue, 15 * saturation, 20 * brightness)
    readonly property color surfaceContainerHighest: hsl(hue, 14 * saturation, 24 * brightness)
    readonly property color surfaceVariant: hsl(hue, 12 * saturation, 30 * brightness)
    readonly property color outline: hsl(hue, 10 * saturation, 58 * brightness)
    readonly property color outlineVariant: hsl(hue, 12 * saturation, 36 * brightness)
    readonly property color onSurface: hsl(hue, 12 * saturation, 92)

    signal colorsChanged

    function hsl(h: real, s: real, l: real): color {
        return Qt.hsla(((h % 360) + 360) % 360 / 360, Math.max(0, Math.min(1, s / 100)), Math.max(0, Math.min(1, l / 100)), 1);
    }

    function setEnabled(e: bool): void {
        if (enabled === e) return;
        enabled = e;
        if (enabled) {
            animationTimer.start();
        } else {
            animationTimer.stop();
        }
    }

    function setAnimationSpeed(speed: real): void {
        animationSpeed = Math.max(0.25, Math.min(8.0, speed));
        animationTimer.interval = Math.max(10, Math.round(50 / animationSpeed));
    }

    Timer {
        id: animationTimer

        interval: 50 // 20 FPS default
        repeat: true
        running: false

        onTriggered: {
            root.currentHue = (root.currentHue + 5 * root.animationSpeed) % 360;
            root.colorsChanged();
        }
    }


}
