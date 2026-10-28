import QtQuick
import Quickshell
import Caelestia.I18n
import qs.modules.launcher.services

// `open <name>` / `launch <name>` explicitly launches an application found
// through the existing Apps searcher (same DesktopEntry path as clicking a
// normal app result). `uninstall <name>` / `remove <name>` maps the entry to
// its pacman/AUR/Flatpak package (or stray user .desktop) and removes it.
// Plain app search is untouched; this only adds explicit verbs.
QtObject {
    id: root

    signal installBinaryRequested

    function handleInstallBinary(binaryPath: string, report: var): void {
        if (!binaryPath) {
            if (report)
                report({ title: Tr.tr("No binary selected"), message: "", icon: "error", type: "error" });
            return;
        }
        Apps.installBinary(binaryPath);
        if (report)
            report({ title: Tr.tr("App installed"), message: Qt.baseName(binaryPath), icon: "check_circle", type: "success" });
    }

    function resolve(raw) {
        const s = (raw ?? "").trim();
        if (!s)
            return null;
        const res = Apps.search(s);
        if (!res || res.length === 0)
            return null;
        const low = s.toLowerCase();
        return res.find(e => (e.name ?? "").toLowerCase() === low) ?? res[0];
    }

    function parseApp(raw) {
        const s = (raw ?? "").trim();
        if (!s)
            return { ok: false, error: Tr.tr("Which application? e.g. open firefox") };
        return { ok: true, value: s };
    }

    readonly property var commands: [
        {
            name: "Install",
            aliases: ["add", "create"],
            description: Tr.tr("Install an app from a binary file"),
            icon: "add_circle",
            category: Tr.tr("Applications"),
            keepOpen: true,
            runBare: true,
            run: (v, report) => {
                Apps.installBinaryRequested();
            }
        },
        {
            name: "Open",
            aliases: ["launch", "run"],
            description: Tr.tr("Launch an application by name"),
            icon: "open_in_new",
            category: Tr.tr("Applications"),
            args: {
                type: "custom",
                required: true,
                parse: root.parseApp,
                hint: "app name"
            },
            run: (v, report) => {
                const entry = root.resolve(v);
                if (!entry) {
                    report({ title: Tr.tr("No app named %1").arg(v), message: "", icon: "error", type: "error" });
                    return;
                }
                Apps.launch(entry);
                report({ title: entry.name, message: Tr.tr("Launching"), icon: "info" ?? "open_in_new", type: "success" });
            }
        },
        {
            name: "Uninstall",
            aliases: ["remove", "delete"],
            description: Tr.tr("Remove an application (pacman / Flatpak)"),
            icon: "delete",
            category: Tr.tr("Applications"),
            // Keep the launcher open: Uninstall reports back via toast once
            // the resolver + remover processes finish.
            keepOpen: true,
            args: {
                type: "custom",
                required: true,
                parse: root.parseApp,
                hint: "app name"
            },
            // CommandRegistry asks this before running; the actual package
            // lookup happens in run() (async), so the prompt names the app.
            confirm: raw => ({
                title: Tr.tr("Uninstall \"%1\"?").arg((raw ?? "").trim()),
                accept: Tr.tr("Uninstall")
            }),
            run: (v, report) => {
                const entry = root.resolve(v);
                if (!entry) {
                    report({ title: Tr.tr("No app named %1").arg(v), message: "", icon: "error", type: "error" });
                    return;
                }
                Uninstall.doRemove(entry, report);
            }
        }
    ]
}
