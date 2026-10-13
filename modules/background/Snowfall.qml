pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services

// Desktop-only snowfall. Instantiated inside Background.qml so it renders
// on the background layer, behind windows and panels.
Item {
    id: root

    required property ShellScreen screen

    property var states: []
    property real elapsed: 0

    // A fullscreen window covers the desktop, so snow isn't visible — stop ticking
    readonly property bool covered: (Hypr.monitorFor(screen)?.activeWorkspace?.toplevels?.values ?? []).some(t => (t.lastIpcObject?.fullscreen ?? 0) > 1)

    opacity: Snow.enabled && Snow.count > 0 ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {
            type: Anim.SlowEffects
        }
    }

    function rand(lo: real, hi: real): real {
        return lo + Math.random() * (hi - lo);
    }

    function makeState(scatterY: bool): var {
        const size = rand(Snow.minSize, Snow.maxSize);
        // 0..1 fraction across the size range, used for depth scaling
        const sizeFrac = Snow.maxSize > Snow.minSize ? (size - Snow.minSize) / (Snow.maxSize - Snow.minSize) : 0.5;
        let speed = rand(Snow.minSpeed, Snow.maxSpeed);
        if (Snow.depth)
            speed *= 0.6 + sizeFrac * 0.8;
        const opacity = rand(Snow.minOpacity, Snow.maxOpacity);
        return {
            bx: Math.random() * Math.max(1, root.width),
            y: scatterY ? Math.random() * Math.max(1, root.height) : -size - rand(0, 60),
            size,
            speed,
            phase: Math.random() * Math.PI * 2,
            swayAmp: Snow.sway * rand(0.4, 1.0),
            opacity,
            rot: Math.random() * 360,
            rotDir: Math.random() < 0.5 ? -1 : 1,
            rotFrac: Math.random(),
            age: 0,
            lifetime: rand(Snow.minLifetime, Snow.maxLifetime)
        };
    }

    function rebuild(): void {
        const n = Snow.enabled ? Snow.count : 0;
        const next = [];
        for (let i = 0; i < n; i++)
            next.push(makeState(true));
        states = next;
        // Rebuild delegates to match; init happens in onItemAdded
        rep.model = 0;
        rep.model = n;
    }

    function restyle(): void {
        // Live-update look params without resetting positions
        for (let i = 0; i < states.length; i++) {
            const item = rep.itemAt(i);
            const st = states[i];
            if (!item || !st)
                continue;
            item.width = st.size;
            item.height = st.size;
            item.radius = Snow.shape === 0 ? st.size / 2 : Math.min(3, st.size / 4);
            item.opacity = st.opacity;
            item.color = Snow.color;
        }
    }

    function respawn(index: int, item: Item, scatter: bool): void {
        const fresh = makeState(scatter);
        if (!scatter)
            fresh.bx = Math.random() * Math.max(1, root.width);
        states[index] = fresh;
        item.width = fresh.size;
        item.height = fresh.size;
        item.radius = Snow.shape === 0 ? fresh.size / 2 : Math.min(3, fresh.size / 4);
        item.opacity = fresh.opacity;
        item.color = Snow.color;
        item.rotation = fresh.rot;
        item.scale = 1;
        item.x = fresh.bx;
        item.y = fresh.y;
    }

    function tick(frameTime: real): void {
        // FrameAnimation.frameTime is in seconds; clamp spikes (e.g. after suspend)
        const dt = Math.min(0.1, frameTime);
        elapsed += dt;
        const w = root.width;
        const h = root.height;
        if (w <= 0 || h <= 0)
            return;
        const wind = Snow.wind;
        const swayFreq = Snow.swaySpeed * Math.PI * 2;
        const spin = Snow.spin;
        const decay = Snow.decayEnabled;
        const shrinkTime = Math.max(0.05, Snow.shrinkTime);
        for (let i = 0; i < states.length; i++) {
            const item = rep.itemAt(i);
            const st = states[i];
            if (!item || !st)
                continue;
            st.y += st.speed * dt;
            st.bx += wind * st.speed * 0.6 * dt;
            const margin = st.size + 12;
            if (st.y > h + margin) {
                respawn(i, item, false);
                continue;
            }
            // Lifetime decay: shrink to nothing once past the lifetime, then respawn
            let sc = 1;
            if (decay) {
                st.age = (st.age || 0) + dt;
                if (st.age > (st.lifetime || 0)) {
                    const k = (st.age - st.lifetime) / shrinkTime;
                    if (k >= 1) {
                        respawn(i, item, false);
                        continue;
                    }
                    sc = 1 - k;
                }
            }
            if (st.bx < -margin)
                st.bx = w + margin;
            else if (st.bx > w + margin)
                st.bx = -margin;
            item.scale = sc;
            item.x = st.bx + Math.sin(elapsed * swayFreq + st.phase) * st.swayAmp;
            item.y = st.y;
            if (spin)
                item.rotation += st.rotDir * Snow.spinSpeed * (0.3 + st.rotFrac * 0.7) * dt;
        }
    }

    Repeater {
        id: rep

        delegate: Rectangle {
            antialiasing: true
            // Shrink towards the flake center during lifetime decay
            transformOrigin: Item.Center
        }

        onItemAdded: (index, item) => {
            const st = root.states[index];
            if (!st)
                return;
            item.width = st.size;
            item.height = st.size;
            item.radius = Snow.shape === 0 ? st.size / 2 : Math.min(3, st.size / 4);
            item.opacity = st.opacity;
            item.color = Snow.color;
            item.rotation = st.rot;
            item.scale = 1;
            item.x = st.bx;
            item.y = st.y;
        }
    }

    FrameAnimation {
        running: root.opacity > 0 && !root.covered
        onTriggered: root.tick(frameTime)
    }

    // Full rebuild when population or distribution changes
    Connections {
        target: Snow
        function onCountChanged(): void {
            root.rebuild();
        }
        function onEnabledChanged(): void {
            root.rebuild();
        }
        function onMinSizeChanged(): void {
            root.rebuild();
        }
        function onMaxSizeChanged(): void {
            root.rebuild();
        }
        function onMinSpeedChanged(): void {
            root.rebuild();
        }
        function onMaxSpeedChanged(): void {
            root.rebuild();
        }
        function onDepthChanged(): void {
            root.rebuild();
        }
        function onSwayChanged(): void {
            root.rebuild();
        }
        // Purely visual changes, no position reset
        function onColorChanged(): void {
            root.restyle();
        }
        function onShapeChanged(): void {
            root.restyle();
        }
        function onMinOpacityChanged(): void {
            root.rebuild();
        }
        function onMaxOpacityChanged(): void {
            root.rebuild();
        }
        function onDecayEnabledChanged(): void {
            root.rebuild();
        }
        function onMinLifetimeChanged(): void {
            root.rebuild();
        }
        function onMaxLifetimeChanged(): void {
            root.rebuild();
        }
    }

    Component.onCompleted: rebuild()
}
