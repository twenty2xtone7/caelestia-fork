import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.modules.launcher.services
import qs.services

// Utilities: translation (delegates to the existing translate mini-app /
// TranslateService), session toggles that already exist (game mode, night
// mode, do-not-disturb) and compression via the `zip` CLI.
//
// Nothing here opens a shell: compression builds a fixed argv list and
// validates the chosen path first.
QtObject {
    id: root

    property var _report: null
    property string _target: ""

    // --- translate one-shot ------------------------------------------------
    // Listens to TranslateService.finished (emitted only after result/error
    // are final) and matches on the captured generation, so a late older
    // request can never overwrite a newer one. No sleeps, no polling: purely
    // event-driven. Right-click opens the full editor mini-app instead.
    property int _oneShotGen: -1
    property var _oneShotReport: null
    property string _oneShotInput: ""

    function startTranslate(v, report) {
        // Engine switch carries no text: toast only, clipboard untouched.
        if (v.provider !== undefined) {
            root.switchProvider(v.provider, report);
            return;
        }
        if (v.target)
            TranslateService.targetCode = v.target;
        TranslateService.input = v.text;
        root._oneShotReport = report;
        root._oneShotInput = v.text;
        // Expecting: adopt the generation from the finished signal if this
        // request completes synchronously (offline / same-language). For an
        // async request nothing fires during translate(), so adopt the
        // current id right after.
        root._oneShotGen = -2;
        TranslateService.translate();
        if (root._oneShotGen === -2)
            root._oneShotGen = TranslateService.currentRequestId;
    }

    property Connections translateConn: Connections {
        target: TranslateService

        function onFinished(generation, result, error): void {
            root.handleTranslateFinished(generation, result, error);
        }
    }

    function handleTranslateFinished(generation, result, error) {
        if (root._oneShotGen === -2) {
            // Our own request finished synchronously inside translate().
            root._oneShotGen = generation;
        }
        if (!root._oneShotReport || generation !== root._oneShotGen) {
            console.info(`[Translate] one-shot ignored finished #${generation} (waiting for #${root._oneShotGen})`);
            return; // not ours, or superseded by a newer request
        }
        const report = root._oneShotReport;
        const input = root._oneShotInput;
        root._oneShotReport = null;
        root._oneShotGen = -1;
        root._oneShotInput = "";
        console.info(`[Translate] one-shot #${generation} notification shown`);

        if (error && !result) {
            report({ title: Tr.tr("Translate"), message: Tr.tr("Translation failed: %1").arg(error), icon: "error", type: "error" });
            return;
        }
        const out = result ?? "";
        if (!out) {
            // Never show a blank notification and never reuse old text.
            report({ title: Tr.tr("Translate"), message: Tr.tr("Translation returned an empty result."), icon: "error", type: "error" });
            return;
        }
        // Always expose the complete translation, even when it is long.
        Quickshell.clipboardText = out;

        if (out.length <= 100) {
            report({ title: Tr.tr("Translate"), message: input + " => " + out, icon: "translate", type: "success" });
        } else {
            // Long results live in the clipboard; the toast just says so.
            report({
                title: Tr.tr("Translate"),
                message: Tr.tr("input too long, copied to clipboard"),
                icon: "translate",
                type: "success"
            });
        }
    }

    function _resolveLangQuery(q) {
        const query = (q ?? "").trim();
        if (!query)
            return "";
        const parts = query.split(/[\\/]/).map(p => p.trim()).filter(p => p.length > 0);
        for (const part of parts) {
            const code = TranslateService.resolveLanguage(part);
            if (code)
                return code;
        }
        return TranslateService.resolveLanguage(query);
    }

    function parseTranslate(raw) {
        const s = raw.trim();
        if (s === "")
            return { ok: false, error: Tr.tr("What should I translate?") };
        // Engine switch: translate /trpro google  (or /provider)
        const pm = s.match(/^\/(trpro|provider)\b\s*(.*)$/i);
        if (pm)
            return { ok: true, value: { provider: (pm[2] ?? "").trim().toLowerCase() } };
        // A lone slash starts a flag, not a translation.
        if (s.startsWith("/"))
            return { ok: false, error: Tr.tr("Unknown flag — try /trpro <engine>") };
        // New flexible syntax: "text > language" (separator optional).
        const gt = s.match(/^(.*?)\s*>\s*(.*)$/);
        if (gt) {
            const text = (gt[1] ?? "").trim();
            const langPart = (gt[2] ?? "").trim();
            if (!text)
                return { ok: false, error: Tr.tr("What should I translate?") };
            if (!langPart)
                return { ok: false, error: Tr.tr("Target language is missing — try: translate <text> > <language>") };
            const code = _resolveLangQuery(langPart);
            if (!code)
                return { ok: false, error: Tr.tr("Unrecognized target language \"%1\"").arg(langPart) };
            return { ok: true, value: { text: text, target: code } };
        }

        // Legacy trailing language: "translate hello en" / "translate hello English".
        const tokens = s.split(/\s+/);
        if (tokens.length >= 2) {
            for (let n = Math.min(3, tokens.length - 1); n >= 1; n--) {
                const langQuery = tokens.slice(tokens.length - n).join(" ");
                const code = _resolveLangQuery(langQuery);
                if (code) {
                    const text = tokens.slice(0, tokens.length - n).join(" ").trim();
                    if (text)
                        return { ok: true, value: { text: text, target: code } };
                }
            }
        }

        // Backward-compat: old strict trailing 2-letter code.
        const m = s.match(/^(.*?)(?:\s+([a-z]{2}))$/i);
        if (m && m[2]) {
            const code = m[2].toLowerCase();
            const known = TranslateService.languages.some(l => l.code === code);
            if (known && m[1].trim() !== "")
                return { ok: true, value: { text: m[1].trim(), target: code } };
        }

        return { ok: true, value: { text: s, target: "" } };
    }

    // Argument completion for the /trpro flag: typing "translate /" offers
    // one row per engine; the rows run the switch directly when selected.
    function suggestTranslate(partial) {
        const p = (partial ?? "").trim().toLowerCase();
        if (!p.startsWith("/"))
            return [];
        const out = [];
        for (const prov of TranslateService.providers) {
            const cand = "/trpro " + prov.id;
            if (cand.startsWith(p) || prov.id.startsWith(p.replace(/^\//, "")))
                out.push({ value: { provider: prov.id }, label: "Translate /trpro " + prov.id });
        }
        return out;
    }

    function switchProvider(name, report) {
        const ids = TranslateService.providers.map(p => p.id);
        if (!name) {
            report({ title: Tr.tr("Translate provider"), message: Tr.tr("Current: %1 — available: %2").arg(TranslateService.providerName).arg(ids.join(", ")), icon: "translate", type: "info" });
            return;
        }
        const hit = TranslateService.providers.find(p => p.id === name);
        if (!hit) {
            report({ title: Tr.tr("Translate"), message: Tr.tr("Unknown provider \"%1\" — available: %2").arg(name).arg(ids.join(", ")), icon: "error", type: "error" });
            return;
        }
        // Persists to disk via TranslateService's providerStorage.
        TranslateService.providerId = hit.id;
        report({ title: Tr.tr("Translate provider"), message: Tr.tr("Switched to %1").arg(hit.name), icon: "translate", type: "success" });
    }

    // --- compress ------------------------------------------------------------
    readonly property var _safeName: /^[A-Za-z0-9._ -]+$/

    function parseCompress(raw) {
        const s = raw.trim().replace(/^["']|["']$/g, "");
        if (s === "")
            return { ok: false, error: Tr.tr("Select a file or folder to compress") };
        return { ok: true, value: s };
    }

    property Process existsProc: Process {
        onExited: code => {
            if (code !== 0) {
                if (root._report)
                    root._report({ title: Tr.tr("Path not found"), message: root._target, icon: "error", type: "error" });
                root._report = null;
                return;
            }
            root.afterExists(root._target);
        }
    }

    property Process zipProc: Process {
        onExited: code => {
            if (!root._report)
                return;
            if (code === 0)
                root._report({ title: Tr.tr("Compressed"), message: root._target, icon: "folder_zip", type: "success" });
            else
                root._report({ title: Tr.tr("Compression failed"), message: root._target, icon: "error", type: "error" });
            root._report = null;
        }
    }

    function startCompress(path, report) {
        root._report = report;
        root._target = path;
        // Existence check first (no shell).
        root.existsProc.command = ["test", "-e", path];
        root.existsProc.running = true;
    }

    function afterExists(path) {
        // zip -r <path>.zip <basename> run from the parent directory.
        const idx = path.lastIndexOf("/");
        const dir = idx >= 0 ? path.slice(0, idx) || "/" : ".";
        const base = idx >= 0 ? path.slice(idx + 1) : path;
        root.zipProc.command = ["zip", "-r", "-y", `${path}.zip`, base];
        root.zipProc.workingDirectory = dir;
        root.zipProc.running = true;
    }

    readonly property var commands: [
        {
            name: "Translate",
            aliases: ["trans", "tr"],
            description: Tr.tr("Translate text (right-click to edit / long text)"),
            icon: "translate",
            category: Tr.tr("Utilities"),
            // Keep the launcher open: the result arrives as a toast + clipboard.
            keepOpen: true,
            args: {
                type: "custom",
                required: true,
                parse: root.parseTranslate,
                suggestFn: root.suggestTranslate,
                hint: "text [language] | /trpro <engine>"
            },
            altAction: list => {
                // Right-click opens the full editor, prefilled with what was typed.
                let initial = "";
                const t = list?.search?.text ?? "";
                const m = t.replace(/^\/+/, "").match(/^\S+\s+([\s\S]*)$/);
                if (m)
                    initial = m[1].trim();
                Actions.openMiniApp("translate", initial);
                if (list?.search)
                    list.search.text = GlobalConfig.launcher.actionPrefix;
            },
            run: (v, report) => root.startTranslate(v, report)
        },
        {
            name: "Game mode",
            aliases: ["gaming", "performance"],
            description: Tr.tr("Toggle Hyprland performance profile"),
            icon: "gamepad",
            category: Tr.tr("Utilities"),
            run: (v, report) => {
                GameMode.enabled = !GameMode.enabled;
                report({ title: GameMode.enabled ? Tr.tr("Game mode enabled") : Tr.tr("Game mode disabled"), message: "", icon: "gamepad", type: "success" });
            }
        },
        {
            name: "Night mode",
            aliases: ["nightlight", "blue light"],
            description: Tr.tr("Toggle night light (right-click for intensity)"),
            icon: "nightlight",
            category: Tr.tr("Utilities"),
            // Right-click opens the intensity mini-app instead of toggling.
            altAction: list => {
                Actions.openMiniApp("night", "");
                if (list?.search)
                    list.search.text = GlobalConfig.launcher.actionPrefix;
            },
            run: (v, report) => {
                Night.toggle();
                report({ title: Night.enabled ? Tr.tr("Night mode enabled") : Tr.tr("Night mode disabled"), message: "", icon: "nightlight", type: "success" });
            }
        },
        {
            name: "Do not disturb",
            aliases: ["dnd"],
            description: Tr.tr("Toggle do not disturb"),
            icon: "do_not_disturb_on",
            category: Tr.tr("Utilities"),
            run: (v, report) => {
                Notifs.dnd = !Notifs.dnd;
                report({ title: Notifs.dnd ? Tr.tr("Do not disturb enabled") : Tr.tr("Do not disturb disabled"), message: "", icon: "do_not_disturb_on", type: "success" });
            }
        },
        {
            name: "Compress",
            aliases: ["zip"],
            description: Tr.tr("Zip a file or folder (path)"),
            icon: "folder_zip",
            category: Tr.tr("Utilities"),
            args: {
                type: "custom",
                required: true,
                parse: root.parseCompress,
                hint: "path"
            },
            run: (v, report) => root.startCompress(v, report)
        }
    ]
}
