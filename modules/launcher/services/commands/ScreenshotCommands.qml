import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n

// Screenshots reuse the existing `caelestia screenshot` CLI / AreaPicker
// overlay (grim + slurp under the hood). No new dependency is introduced.
// `window` grabs the focused Hyprland window geometry and captures it with
// grim directly, since the area picker has no window mode.
QtObject {
    id: root

    function parseActiveWindow(json) {
        try {
            const w = JSON.parse(json);
            if (!w || !w.at || w.width <= 0 || w.height <= 0)
                return null;
            return { x: w.at[0], y: w.at[1], w: w.width, h: w.height };
        } catch (e) {
            return null;
        }
    }

    property var _report: null
    property var _failMsg: ""

    // Window capture: read active window geometry, then grim that region.
    property Process windowInfo: Process {
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parseActiveWindow(text);
                if (!r) {
                    if (root._report)
                        root._report({ title: Tr.tr("Screenshot failed"), message: root._failMsg, icon: "error", type: "error" });
                    return;
                }
                const geo = `${r.x},${r.y} ${r.w}x${r.h}`;
                Quickshell.execDetached(["sh", "-c", 'file="$(mktemp --suffix=.png /tmp/screenshot-XXXXXX.png)"; grim -g "$1" "$file" && wl-copy < "$file" && notify-send -a caelestia-cli -i "$file" "Screenshot taken" "Window capture copied to clipboard"', "shot", geo]);
                if (root._report)
                    root._report({ title: Tr.tr("Screenshot taken"), message: Tr.tr("Window copied to clipboard"), icon: "screenshot_monitor", type: "success" });
            }
        }
    }

    readonly property var commands: [
        {
            name: "Screenshot",
            aliases: ["ss", "shot"],
            description: Tr.tr("Capture the screen"),
            icon: "screenshot_monitor",
            category: Tr.tr("Screenshot"),
            args: {
                type: "enum",
                optional: true,
                values: ["region", "window", "freeze"],
                hint: "region / window / freeze"
            },
            run: (v, report) => {
                if (v === "window") {
                    root._report = report;
                    root._failMsg = Tr.tr("No focused window");
                    root.windowInfo.running = true;
                } else if (v === "region") {
                    Quickshell.execDetached(["caelestia", "screenshot", "-r"]);
                    report({ title: Tr.tr("Screenshot"), message: Tr.tr("Select a region"), icon: "screenshot_region", type: "info" });
                } else if (v === "freeze") {
                    Quickshell.execDetached(["caelestia", "screenshot", "-r", "-f"]);
                    report({ title: Tr.tr("Screenshot"), message: Tr.tr("Select a region (frozen)"), icon: "screenshot_region", type: "info" });
                } else {
                    Quickshell.execDetached(["caelestia", "screenshot"]);
                    report({ title: Tr.tr("Screenshot"), message: Tr.tr("Select an area"), icon: "screenshot_monitor", type: "info" });
                }
            }
        }
    ]
}
