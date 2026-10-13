import QtQuick
import Quickshell
import Caelestia.I18n
import qs.services

// Audio commands reuse the existing Pipewire-backed Audio service
// (qs.services.Audio). No second backend, no pactl/pamixer dependency.
QtObject {
    readonly property var commands: [
        {
            name: "Volume",
            aliases: ["vol", "sound"],
            description: Tr.tr("Set system volume (0-150)"),
            icon: "volume_up",
            category: Tr.tr("Audio"),
            args: {
                type: "int",
                min: 0,
                max: 150,
                required: true,
                hint: "0-150",
                // Contextual autocomplete values.
                suggestions: ["25", "50", "75", "100"]
            },
            run: (v, report) => {
                Audio.setVolume(v / 100);
                report({ title: Tr.tr("Volume set to %1%").arg(v), message: "", icon: "volume_up", type: "success" });
            }
        },
        {
            name: "Mute",
            aliases: [],
            description: Tr.tr("Toggle mute"),
            icon: "volume_off",
            category: Tr.tr("Audio"),
            run: (v, report) => {
                const node = Audio.sink;
                if (!node?.audio) {
                    report({ title: Tr.tr("No audio output"), message: "", icon: "error", type: "error" });
                    return;
                }
                node.audio.muted = !node.audio.muted;
                report({ title: node.audio.muted ? Tr.tr("Muted") : Tr.tr("Unmuted"), message: "", icon: node.audio.muted ? "volume_off" : "volume_up", type: "success" });
            }
        },
        {
            name: "Unmute",
            aliases: [],
            description: Tr.tr("Unmute the system"),
            icon: "volume_up",
            category: Tr.tr("Audio"),
            run: (v, report) => {
                const node = Audio.sink;
                if (node?.audio)
                    node.audio.muted = false;
                report({ title: Tr.tr("Unmuted"), message: "", icon: "volume_up", type: "success" });
            }
        }
    ]
}
