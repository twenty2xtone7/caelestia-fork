pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n

// Backend for the launcher fan mini-app.
// Reads/writes /sys/kernel/thinkpad_fan_ctl (thinkpad_fan_ctl kernel module).
// The level/auto_mode nodes are world-writable (0666), so no sudo is needed.
Singleton {
    id: root

    readonly property string ctlDir: "/sys/kernel/thinkpad_fan_ctl"
    readonly property string levelPath: `${ctlDir}/level`
    readonly property string tempPath: `${ctlDir}/temp`
    readonly property string speedPath: `${ctlDir}/speed`

    // Set from the backend; empty while unknown. currentLevel drives the mode
    // label, available gates the `/` entry (hidden when the module isn't
    // loaded).
    property bool available: false
    property string currentLevel: ""
    property string tempC: ""
    property string rpm: ""
    property string tempText: ""

    // Slider rail position 0..9: 0 = auto, 1..8 = manual levels 0..7,
    // 9 = max. The slider binds to this. It stays put while the backend
    // reports something else, so dragging never fights live updates.
    property int sliderPos: 4

    function valueForPos(p: int): string {
        if (p <= 0)
            return "auto";
        if (p >= 9)
            return "max";
        return String(p - 1);
    }

    function posForValue(v: string): int {
        if (v === "auto")
            return 0;
        if (v === "max" || v === "full-speed")
            return 9;
        const n = parseInt(v, 10);
        return isNaN(n) ? -1 : n + 1;
    }

    readonly property string modeLabel: {
        const c = root.currentLevel;
        if (c === "auto")
            return Tr.tr("Auto");
        if (c === "full-speed")
            return Tr.tr("Max");
        if (c === "disengaged")
            return Tr.tr("Disengaged");
        if (c !== "" && !isNaN(parseInt(c, 10)))
            return Tr.tr("Level %1").arg(c);
        return Tr.tr("Unknown");
    }

    function updateTempText(): void {
        tempText = tempC !== "" && rpm !== "" ? `${tempC} · ${rpm}` : tempC + rpm;
    }

    function setLevel(value: string): void {
        const p = posForValue(value);
        if (p >= 0)
            sliderPos = p;
        Quickshell.execDetached(["sh", "-c", `echo ${value} > ${root.levelPath}`]);
    }

    function setSliderPos(p: int): void {
        setLevel(valueForPos(Math.min(9, Math.max(0, p))));
    }

    // Relative step for wheel/arrow control. No-op at the auto/max rails so
    // the EC isn't rewritten when nothing changes.
    function nudge(delta: int): void {
        const p = Math.min(9, Math.max(0, sliderPos + delta));
        if (p !== sliderPos)
            setLevel(valueForPos(p));
    }

    function reload(): void {
        getLevel.running = true;
        getTemp.running = true;
        getSpeed.running = true;
    }

    // Cheap liveness probe used while the backend is missing. Re-runs only the
    // level read; a successful read sets `available` (see getLevel below) and
    // the recheck timer then stops itself.
    function probe(): void {
        getLevel.running = true;
    }

    // `/` action-list entry. Same shape as Actions' translate/music/clipboard
    // pseudo-actions so ActionItem and the onClicked dispatch work unchanged.
    readonly property list<string> fanKeywords: ["fan", "cooling"]

    function matchesFan(text: string): bool {
        const inner = text.slice(GlobalConfig.launcher.actionPrefix.length).trim().toLowerCase();
        if (!inner)
            return true;
        const first = inner.split(" ")[0];
        return fanKeywords.some(k => k.startsWith(first));
    }

    readonly property QtObject fanAction: QtObject {
        readonly property string name: Tr.tr("Fan")
        readonly property string desc: Tr.tr("Control ThinkPad fan with a slider")
        readonly property string icon: "mode_fan"
        readonly property list<string> command: ["fan"]
        readonly property bool enabled: true
        readonly property bool dangerous: false

        function onClicked(list: var): void {
            Actions.openMiniApp("fan", "");
        }
    }

    function fanMatches(text: string): var {
        if (!root.available)
            return [];
        return matchesFan(text) ? [fanAction] : [];
    }

    // Re-probe the backend until it appears. `available` starts false and is
    // only re-evaluated by getLevel, so without this the `/` fan entry would
    // stay hidden for the rest of the shell session if Caelestia started
    // before the kernel module was ready (or if it is (re)loaded later). The
    // timer runs only while unavailable; a successful getLevel stops it and
    // `available` going false again restarts it (e.g. after suspend/resume or
    // a module reload).
    Timer {
        id: recheck

        interval: 2000
        repeat: true
        running: !root.available
        onTriggered: root.probe()
    }

    Process {
        id: getLevel

        running: true
        command: ["cat", root.levelPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                root.currentLevel = v;
                // Non-empty output == module present with a readable level node.
                root.available = v !== "";
                const p = root.posForValue(v);
                if (p >= 0)
                    root.sliderPos = p;
            }
        }
        // If the process fails to launch read the file at all, make sure we
        // don't get stuck thinking the backend is present.
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.available = false;
        }
    }

    Process {
        id: getTemp

        command: ["cat", root.tempPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const mC = parseInt(text.trim(), 10);
                root.tempC = isNaN(mC) ? "" : `${Math.round(mC / 1000)}°C`;
                root.updateTempText();
            }
        }
    }

    Process {
        id: getSpeed

        command: ["cat", root.speedPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const speed = parseInt(text.trim(), 10);
                root.rpm = isNaN(speed) ? "" : `${speed} RPM`;
                root.updateTempText();
            }
        }
    }
}
