import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n

// Process management. `kill <name>` matches the process name exactly
// (`pkill -x`) and always asks for confirmation. The name is validated to a
// strict character set and passed as a single argv element - never through a
// shell - so arbitrary input cannot become a command.
QtObject {
    id: root

    readonly property var _nameRe: /^[A-Za-z0-9_.+:@-]+$/
    property var _report: null
    property string _target: ""

    function validateName(raw) {
        const s = raw.trim();
        if (s === "")
            return { ok: false, error: Tr.tr("Which process? e.g. kill firefox") };
        if (!root._nameRe.test(s))
            return { ok: false, error: Tr.tr("Invalid process name") };
        return { ok: true, value: s };
    }

    property Process killer: Process {
        onExited: code => {
            if (!root._report)
                return;
            if (code === 0)
                root._report({ title: Tr.tr("Killed %1").arg(root._target), message: "", icon: "close", type: "success" });
            else
                root._report({ title: Tr.tr("No process named %1").arg(root._target), message: "", icon: "error", type: "warning" });
            root._report = null;
        }
    }

    readonly property var commands: [
        {
            name: "Kill",
            aliases: ["pkill", "terminate"],
            description: Tr.tr("Terminate a process by exact name"),
            icon: "close",
            category: Tr.tr("Process"),
            dangerous: false,
            args: {
                type: "custom",
                required: true,
                parse: root.validateName,
                hint: "process name"
            },
            // Dynamic confirmation so the prompt names the target.
            confirm: raw => ({
                title: Tr.tr("Kill \"%1\"?").arg(raw.trim()),
                accept: Tr.tr("Kill")
            }),
            run: (v, report) => {
                root._report = report;
                root._target = v;
                root.killer.command = ["pkill", "-x", v];
                root.killer.running = true;
            }
        }
    ]
}
