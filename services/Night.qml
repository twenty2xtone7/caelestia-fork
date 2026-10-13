pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services

Singleton {
    id: root

    property alias enabled: props.enabled
    property alias temperature: props.temperature

    readonly property list<var> presets: [
        { name: Tr.trCtx("Candle", "night mode preset"), temperature: 1800 },
        { name: Tr.trCtx("Sunset", "night mode preset"), temperature: 3000 },
        { name: Tr.trCtx("Evening", "night mode preset"), temperature: 4000 },
        { name: Tr.trCtx("Soft", "night mode preset"), temperature: 5000 }
    ]

    function toggle(): void {
        props.enabled = !props.enabled;
    }

    function sendTemperature(): void {
        if (enabled)
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(Math.round(temperature))]);
    }

    onEnabledChanged: {
        if (enabled) {
            // Make sure the daemon is up before sending the temperature.
            daemonCheck.running = true;
        } else {
            Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
        }
    }

    onTemperatureChanged: {
        if (enabled)
            root.sendTemperature();
    }

    // Re-apply after (re)start: the daemon does not survive session end,
    // but the toggle state does (PersistentProperties).
    Component.onCompleted: {
        if (enabled)
            daemonCheck.running = true;
    }

    PersistentProperties {
        id: props

        property bool enabled: false
        property int temperature: 4000

        reloadableId: "nightMode"
    }

    Process {
        id: daemonCheck

        command: ["pgrep", "-x", "hyprsunset"]
        onExited: code => { // qmllint disable signal-handler-parameters
            if (code !== 0)
                Quickshell.execDetached(["hyprsunset"]);
            applyTimer.restart();
        }
    }

    Timer {
        id: applyTimer

        interval: 800
        onTriggered: root.sendTemperature()
    }
}
