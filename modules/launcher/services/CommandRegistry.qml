pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services
import "commands"

// Universal Action Launcher: a registry of commands that turn launcher input
// into validated desktop actions.
//
// Design goals (see CHANGES-style notes at the bottom of this file):
//  * modular   - every category is its own file under ./commands
//  * safe      - handlers build argv arrays; user text never reaches a shell
//  * fast      - matching is pure string work; processes run only on selection
//  * native UI - results are plain objects shaped like Actions' entries, so the
//                existing ActionItem delegate and list animations are reused
//
// Command descriptor shape:
//   name         display name and default invocation word ("Volume")
//   aliases      extra invocation words ("vol")
//   description  subtitle
//   icon         Material symbol
//   category     optional grouping label
//   dangerous    if true, hidden unless GlobalConfig.launcher.enableDangerousActions
//   args         optional { type, required, min, max, hint, suggestions, suggestFn, parse }
//   confirm      optional bool, {title,accept} or value=>{title,accept}
//   run          (validatedValue, report) => void
Singleton {
    id: root

    readonly property SystemCommands system: SystemCommands {}
    readonly property ScreenshotCommands screenshot: ScreenshotCommands {}
    readonly property ProcessCommands process: ProcessCommands {}
    readonly property ChatCommands chat: ChatCommands {}
    readonly property AppCommands apps: AppCommands {}
    readonly property UtilitiesCommands utilities: UtilitiesCommands {}

    readonly property var commands: [
        ...system.commands,
        ...screenshot.commands,
        ...process.commands,
        ...chat.commands,
        ...apps.commands,
        ...utilities.commands
    ]

    // ----- execution feedback -------------------------------------------------
    // Uses the existing Caelestia Toaster (three-argument form, like every
    // other service) so no new notification path is introduced.
    function report(info) {
        if (!info)
            return;
        let type = Toast.Info;
        if (info.type === "success")
            type = Toast.Success;
        else if (info.type === "error")
            type = Toast.Error;
        else if (info.type === "warning")
            type = Toast.Warning;
        Toaster.toast(info.title ?? "", info.message ?? "", info.icon ?? "check_circle", type);
    }

    function error(message) {
        return { ok: false, error: message };
    }

    // ----- argument validation ------------------------------------------------
    // Central, explicit validation. No handler touches raw input directly.
    function validate(entry, raw) {
        const a = entry.args;
        if (!a)
            return { ok: true, value: undefined };
        if (a.type === "custom") {
            if (typeof a.parse === "function")
                return a.parse(raw);
            return { ok: true, value: raw };
        }
        const s = (raw ?? "").trim();
        if (s === "") {
            if (a.required)
                return error(Tr.tr("A value is required"));
            return { ok: true, value: undefined };
        }
        if (a.type === "int") {
            // Reject "50abc" style input: must be a clean integer.
            if (!/^-?\d+$/.test(s))
                return error(Tr.tr("Expected a whole number"));
            const n = parseInt(s, 10);
            if (a.min !== undefined && n < a.min)
                return error(Tr.tr("Minimum is %1").arg(a.min));
            if (a.max !== undefined && n > a.max)
                return error(Tr.tr("Maximum is %1").arg(a.max));
            return { ok: true, value: n };
        }
        if (a.type === "bool") {
            const l = s.toLowerCase();
            if (l === "on" || l === "true" || l === "1" || l === "yes")
                return { ok: true, value: "on" };
            if (l === "off" || l === "false" || l === "0" || l === "no")
                return { ok: true, value: "off" };
            return error(Tr.tr("Expected on or off"));
        }
        if (a.type === "enum") {
            const l = s.toLowerCase();
            const hit = (a.values ?? []).find(v => v.toLowerCase() === l);
            if (hit === undefined)
                return error(Tr.tr("Expected one of: %1").arg((a.values ?? []).join(", ")));
            return { ok: true, value: hit };
        }
        return { ok: true, value: s };
    }

    // ----- matching -----------------------------------------------------------
    function transform(text) {
        const p = GlobalConfig.launcher.actionPrefix;
        return text.startsWith(p) ? text.slice(p.length) : text;
    }

    function keys(entry) {
        return [entry.name.toLowerCase(), ...(entry.aliases ?? []).map(a => a.toLowerCase())];
    }

    // Exact command word: the whole input equals a key, or starts with a key
    // followed by a space (arguments present). Prefix-only input is NOT an
    // invocation, so ordinary app searches are never hijacked.
    function invocation(text) {
        const s = transform(text).trim().replace(/\s+/g, " ");
        if (!s)
            return null;
        const low = s.toLowerCase();
        for (const entry of root.commands) {
            for (const k of keys(entry)) {
                if (low === k)
                    return { entry, rest: "" };
                if (low.startsWith(k + " "))
                    return { entry, rest: s.slice(k.length + 1).trim() };
            }
        }
        return null;
    }

    function hasInvocation(text) {
        return invocation(text) !== null;
    }

    function visible(entry) {
        return !entry.dangerous || GlobalConfig.launcher.enableDangerousActions;
    }

    function runResult(entry, value, label) {
        return {
            __command: true,
            name: label ?? entry.name,
            desc: entry.description,
            icon: entry.icon ?? "bolt",
            category: entry.category ?? "",
            command: [],
            enabled: true,
            dangerous: entry.dangerous ?? false,
            onClicked: list => root.activate(entry, value, list),
            onAltClicked: entry.altAction ? (list => entry.altAction(list)) : null
        };
    }

    // Fill the search box with a command stub so the user can type the value.
    function fillResult(entry, invocationWord) {
        return {
            __command: true,
            name: Tr.tr("%1 — type a value").arg(entry.name),
            desc: entry.args?.hint ? entry.description + " (" + entry.args.hint + ")" : entry.description,
            icon: entry.icon ?? "bolt",
            category: entry.category ?? "",
            command: [],
            enabled: true,
            dangerous: entry.dangerous ?? false,
            onClicked: list => {
                list.search.text = invocationWord + " ";
                list.search.forceActiveFocus();
            }
        };
    }

    function suggestionResults(entry, invocationWord, partial) {
        const a = entry.args;
        if (!a)
            return [];
        const out = [];
        const push = v => {
            if (!out.some(r => r.name === (entry.name + " " + v)))
                out.push(runResult(entry, v, entry.name + " " + v));
        };
        if (Array.isArray(a.suggestions)) {
            for (const v of a.suggestions)
                push(v);
        }
        if (Array.isArray(a.values)) {
            for (const v of a.values)
                push(v);
        }
        if (typeof a.suggestFn === "function") {
            for (const s of a.suggestFn(partial)) {
                if (s && s.value !== undefined)
                    out.push(runResult(entry, s.value, s.label ?? (entry.name + " " + s.value)));
            }
        }
        out.push(fillResult(entry, invocationWord));
        return out;
    }

    // Prefix autocomplete for a partially typed command word (e.g. "scr").
    function prefixResults(first) {
        const out = [];
        for (const entry of root.commands) {
            if (!visible(entry))
                continue;
            for (const k of keys(entry)) {
                if (k.startsWith(first)) {
                    const w = entry.name.toLowerCase();
                    const invocationWord = w;
                    if (entry.args)
                        out.push(...suggestionResults(entry, invocationWord, ""));
                    else
                        out.push(runResult(entry, undefined, entry.name));
                    break;
                }
            }
        }
        return out;
    }

    function matches(text) {
        const raw = transform(text).trim().replace(/\s+/g, " ");
        if (!raw)
            return [];

        const inv = invocation(text);
        if (inv && visible(inv.entry)) {
            const e = inv.entry;
            // Exact word with no argument.
            if (inv.rest === "") {
                // Opt-in immediate run for side-effect-free commands (e.g.
                // `chat` opens Nexus AI Chat). Validation still runs so run()
                // always gets a well-shaped value, never undefined.
                // Anything else that still needs an argument keeps showing
                // suggestions instead of running immediately.
                if (e.args && e.args.type === "custom" && !e.args.required && e.runBare) {
                    const v0 = root.validate(e, "");
                    if (v0.ok)
                        return [runResult(e, v0.value)];
                }
                if (e.args && (e.args.required || e.args.type === "custom"))
                    return suggestionResults(e, e.name.toLowerCase(), "");
                return [runResult(e, undefined)];
            }
            // Word followed by arguments.
            const v = root.validate(e, inv.rest);
            if (!v.ok)
                return [{
                    __command: true,
                    name: Tr.tr("%1: invalid").arg(e.name),
                    desc: v.error,
                    icon: "error",
                    category: e.category ?? "",
                    command: [],
                    enabled: false,
                    dangerous: false,
                    onClicked: () => {}
                }, fillResult(e, e.name.toLowerCase())];
            // Argument is itself a command word (e.g. "screenshot region").
            if (e.args?.type === "enum" && (e.args.values ?? []).some(x => x.toLowerCase() === inv.rest.toLowerCase()))
                return [runResult(e, v.value, e.name + " " + inv.rest)];
            return [runResult(e, v.value, e.name + " " + inv.rest)];
        }

        // Prefix autocomplete only for a single token; argument typing should
        // not re-scan the whole registry on every keystroke.
        const single = !raw.includes(" ");
        if (single)
            return prefixResults(raw.toLowerCase());
        return [];
    }

    // ----- activation / confirmation -----------------------------------------
    property var pending: null // { entry, value, list }
    property var pendingConfirm: null

    function activate(entry, value, list) {
        if (entry.confirm) {
            let c = typeof entry.confirm === "function" ? entry.confirm(value) : entry.confirm;
            if (c === true)
                c = { title: Tr.tr("Are you sure?"), accept: Tr.tr("Confirm") };
            root.pendingConfirm = c;
            root.pending = { entry, value, list };
            return;
        }
        root.execute(entry, value, list);
    }

    function acceptPending() {
        const p = root.pending;
        root.pending = null;
        root.pendingConfirm = null;
        if (p)
            root.execute(p.entry, p.value, p.list);
    }

    function cancelPending() {
        root.pending = null;
        root.pendingConfirm = null;
    }

    function execute(entry, value, list) {
        try {
            entry.run(value, root.report);
        } catch (e) {
            root.report({ title: Tr.tr("Action failed"), message: String(e), icon: "error", type: "error" });
            return;
        }
        if (!entry.keepOpen && list?.screenState)
            list.screenState.launcher = false;
    }
}
