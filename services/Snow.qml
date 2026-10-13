pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    // General
    property bool enabled: false
    property int count: 150
    property string color: "#ffffff"
    // 0 = round, 1 = square
    property int shape: 0

    // Flake size (px)
    property real minSize: 2
    property real maxSize: 6

    // Opacity
    property real minOpacity: 0.3
    property real maxOpacity: 0.9

    // Fall speed (px/s)
    property real minSpeed: 30
    property real maxSpeed: 120

    // Horizontal drift, -1 (left) to 1 (right)
    property real wind: 0.15
    // Side-to-side sway amplitude (px)
    property real sway: 30
    // Sway oscillation speed (cycles/s)
    property real swaySpeed: 0.6

    // Rotation
    property bool spin: true
    property real spinSpeed: 60

    // Bigger flakes fall faster
    property bool depth: true

    // Lifetime decay: flakes shrink away after a random lifetime (seconds)
    property bool decayEnabled: false
    property real minLifetime: 8
    property real maxLifetime: 20
    property real shrinkTime: 1.5

    function resetDefaults(): void {
        enabled = false;
        count = 150;
        color = "#ffffff";
        shape = 0;
        minSize = 2;
        maxSize = 6;
        minOpacity = 0.3;
        maxOpacity = 0.9;
        minSpeed = 30;
        maxSpeed = 120;
        wind = 0.15;
        sway = 30;
        swaySpeed = 0.6;
        spin = true;
        spinSpeed = 60;
        depth = true;
        decayEnabled = false;
        minLifetime = 8;
        maxLifetime = 20;
        shrinkTime = 1.5;
    }

    function toJson(): var {
        return {
            enabled,
            count,
            color,
            shape,
            minSize,
            maxSize,
            minOpacity,
            maxOpacity,
            minSpeed,
            maxSpeed,
            wind,
            sway,
            swaySpeed,
            spin,
            spinSpeed,
            depth,
            decayEnabled,
            minLifetime,
            maxLifetime,
            shrinkTime
        };
    }

    function clampNum(v: var, lo: real, hi: real, fallback: real): real {
        const n = Number(v);
        if (isNaN(n))
            return fallback;
        return Math.min(hi, Math.max(lo, n));
    }

    function applyData(data: var): void {
        if (!data || typeof data !== "object")
            return;
        // Block saves while applying so a load never triggers a write loop
        applying = true;
        enabled = data.enabled === true;
        count = Math.round(clampNum(data.count, 0, 1000, 150));
        if (typeof data.color === "string" && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$/.test(data.color))
            color = data.color;
        shape = data.shape === 1 ? 1 : 0;
        minSize = clampNum(data.minSize, 1, 30, 2);
        maxSize = clampNum(data.maxSize, 1, 30, 6);
        if (minSize > maxSize)
            maxSize = minSize;
        minOpacity = clampNum(data.minOpacity, 0, 1, 0.3);
        maxOpacity = clampNum(data.maxOpacity, 0, 1, 0.9);
        if (minOpacity > maxOpacity)
            maxOpacity = minOpacity;
        minSpeed = clampNum(data.minSpeed, 5, 800, 30);
        maxSpeed = clampNum(data.maxSpeed, 5, 800, 120);
        if (minSpeed > maxSpeed)
            maxSpeed = minSpeed;
        wind = clampNum(data.wind, -1, 1, 0.15);
        sway = clampNum(data.sway, 0, 300, 30);
        swaySpeed = clampNum(data.swaySpeed, 0, 5, 0.6);
        spin = data.spin !== false;
        spinSpeed = clampNum(data.spinSpeed, 0, 720, 60);
        depth = data.depth !== false;
        decayEnabled = data.decayEnabled === true;
        minLifetime = clampNum(data.minLifetime, 1, 300, 8);
        maxLifetime = clampNum(data.maxLifetime, 1, 300, 20);
        if (minLifetime > maxLifetime)
            maxLifetime = minLifetime;
        shrinkTime = clampNum(data.shrinkTime, 0.1, 30, 1.5);
        applying = false;
    }

    property bool applying: false

    onEnabledChanged: scheduleSave()
    onCountChanged: scheduleSave()
    onColorChanged: scheduleSave()
    onShapeChanged: scheduleSave()
    onMinSizeChanged: scheduleSave()
    onMaxSizeChanged: scheduleSave()
    onMinOpacityChanged: scheduleSave()
    onMaxOpacityChanged: scheduleSave()
    onMinSpeedChanged: scheduleSave()
    onMaxSpeedChanged: scheduleSave()
    onWindChanged: scheduleSave()
    onSwayChanged: scheduleSave()
    onSwaySpeedChanged: scheduleSave()
    onSpinChanged: scheduleSave()
    onSpinSpeedChanged: scheduleSave()
    onDepthChanged: scheduleSave()
    onDecayEnabledChanged: scheduleSave()
    onMinLifetimeChanged: scheduleSave()
    onMaxLifetimeChanged: scheduleSave()
    onShrinkTimeChanged: scheduleSave()

    function scheduleSave(): void {
        if (applying || !loaded)
            return;
        saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 500
        onTriggered: storage.setText(JSON.stringify(root.toJson(), null, 4))
    }

    property bool loaded: false

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/snow.json`
        onLoaded: {
            try {
                root.applyData(JSON.parse(text()));
            } catch (e) {
                console.warn("Snow: failed to parse snow.json, using defaults:", e);
            }
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(JSON.stringify(root.toJson(), null, 4)));
            root.loaded = true;
        }
    }
}
