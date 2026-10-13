pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.I18n

// Maps a launcher DesktopEntry to something removable (pacman/AUR,
// flatpak user/system, or a stray user .desktop) and removes it.
// Resolution goes through assets/resolve-uninstall.py so no shell is
// involved; removal uses fixed argv lists. Nothing here runs as root
// directly: system packages go through pkexec (polkit prompt).
//
// Two entry points:
//   doRemove(entry, report)  - no confirm of its own. Used by the
//                              `uninstall` action, which already asked via
//                              CommandRegistry's confirm dialog.
//   request(entry, list)     - resolves, then raises pendingConfirm with
//                              the package detail. Used by right-click.
//                              CommandConfirmDialog also watches
//                              pendingConfirm (see that file).
Singleton {
    id: root

    readonly property string script: `${Quickshell.shellDir}/assets/resolve-uninstall.py`

    // Set while the right-click confirmation is showing.
    // { title, accept }
    property var pendingConfirm: null

    // Detail side-panel state. The panel pins the entry it was opened with
    // (trash button / Right arrow); Right on another app re-pins.
    property var panelEntry: null
    property var panelList: null
    property bool panelOpen: false
    // Keyboard highlight within the panel buttons: -1 = focus stays in the
    // app list, 0..3 = Launch, Uninstall, Favourite, Hide. Up/Down cycles
    // it while the panel is open; Enter activates; Right on Hide (3) opens
    // the hidden-apps panel.
    property int panelIndex: -1
    // Hidden-apps side panel (second slide-out, right of the detail panel).
    property bool hiddenOpen: false
    // Keyboard highlight within hidden rows, -1 = none. Enter unhides.
    property int hiddenIndex: -1

    function openPanel(entry: var, list: var): void {
        if (!entry || !entry.id)
            return;
        root.panelEntry = entry;
        root.panelList = list ?? null;
        root.panelOpen = true;
        root.panelIndex = -1;
        root.hiddenOpen = false;
        root.hiddenIndex = -1;
    }

    function closePanel(): void {
        root.panelOpen = false;
        root.panelEntry = null;
        root.panelList = null;
        root.panelIndex = -1;
        root.hiddenOpen = false;
        root.hiddenIndex = -1;
    }

    property var _entry: null
    property var _list: null
    property var _report: null
    property string _appName: ""
    property string _kind: ""
    property string _target: ""
    property string _detail: ""
    property string _extra: ""
    property string _removerStderr: ""
    // Second removal stage: leftover loose launcher file after a package
    // removal (pkexec rm, exact resolved path shown in the confirm).
    property string _pendingRm: ""
    property bool _rmStage: false
    // After resolving for request(), the argv to run on accept.
    property var _removerArgv: []
    property bool _removerNeedsPolkit: false

    // One-shot resolve callback. Only one resolution at a time; a second
    // request while busy gets a "busy" toast.
    property var _resolveCb: null

    function toast(title: string, message: string, icon: string, type: var): void {
        Toaster.toast(title, message, icon, type ?? Toast.Info);
    }

    function notifyBusy(): void {
        toast(Tr.tr("Busy"), Tr.tr("Another uninstall is in progress"), "hourglass_empty", Toast.Warning);
    }

    // --- resolution ------------------------------------------------------

    function resolve(entry: var, cb: var): bool {
        if (resolver.running) {
            root.notifyBusy();
            return false;
        }
        if (!entry || !entry.id) {
            toast(Tr.tr("Cannot uninstall"), Tr.tr("Unknown application"), "error", Toast.Error);
            return false;
        }
        root._resolveCb = cb;
        resolver.command = ["python3", root.script, entry.id];
        resolver.running = true;
        return true;
    }

    property Process resolver: Process {
        stdout: StdioCollector {
            onStreamFinished: root.handleResolved(text);
        }
        onExited: (code, status) => {
            // Stdout parsing reports errors; a crash with no output means
            // the helper itself failed.
            if (code !== 0 && !root._resolveCbCalled) {
                const cb = root._resolveCb;
                root._resolveCb = null;
                if (cb)
                    cb("", "", "", "");
            }
        }
    }
    property bool _resolveCbCalled: false

    function handleResolved(text: string): void {
        root._resolveCbCalled = true;
        const cb = root._resolveCb;
        root._resolveCb = null;
        const line = (text ?? "").split("\n").find(l => l.includes("\t")) ?? "";
        const parts = line.split("\t");
        const kind = (parts[0] ?? "").trim();
        const target = (parts[1] ?? "").trim();
        const detail = (parts[2] ?? "").trim();
        const extra = (parts[3] ?? "").trim();
        if (cb)
            cb(kind, target, detail, extra);
        root._resolveCbCalled = false;
    }

    // --- removal ---------------------------------------------------------

    // extra is either "" , "trash:<path>" (trashed alongside target) or
    // "bin:<path>|<owner>" (display-only info about the backing binary).
    function extraTrashPath(extra: string): string {
        return extra.startsWith("trash:") ? extra.slice(6) : "";
    }

    function extraRmPath(extra: string): string {
        return extra.startsWith("rm:") ? extra.slice(3) : "";
    }

    function manualPath(detail: string): string {
        return detail.startsWith("manual:") ? detail.slice(7) : "";
    }

    // Message for kinds that cannot be removed automatically.
    function cannotMessage(detail: string, extra: string): string {
        if (detail === "protected")
            return Tr.tr("System component — removing it would break the system");
        const m = root.manualPath(detail);
        if (m) {
            let msg = Tr.tr("Not managed by pacman — remove manually:\n%1").arg(m);
            const bin = root.extraBinInfo(extra ?? "");
            if (bin && bin.path)
                msg += "\n" + Tr.tr("Program: %1 (%2)").arg(bin.path).arg(root.describeOwner(bin.owner));
            return msg;
        }
        return Tr.tr("No pacman or Flatpak package found");
    }

    function extraBinInfo(extra: string): var {
        if (!extra.startsWith("bin:"))
            return null;
        const rest = extra.slice(4);
        const i = rest.indexOf("|");
        return { path: i < 0 ? rest : rest.slice(0, i), owner: i < 0 ? "" : rest.slice(i + 1) };
    }

    function removerArgv(kind: string, target: string, extra: string): var {
        if (kind === "pacman" || kind === "aur")
            return ["pkexec", "pacman", "-Rns", "--noconfirm", target];
        if (kind === "flatpak-user")
            return ["flatpak", "uninstall", "-y", "--noninteractive", "--user", target];
        if (kind === "flatpak-system")
            return ["pkexec", "flatpak", "uninstall", "-y", "--noninteractive", "--system", target];
        if (kind === "user")
            return ["gio", "trash", "-f", target];
        if (kind === "home-binary" || kind === "prefix-game") {
            const second = root.extraTrashPath(extra);
            if (second)
                return ["gio", "trash", "-f", target, second];
        }
        if (kind === "system-entry")
            return ["pkexec", "rm", "-f", target];
        return [];
    }

    function describeTarget(kind: string, target: string, detail: string, extra: string): string {
        if (kind === "pacman" || kind === "aur") {
            const label = kind === "pacman" ? Tr.tr("pacman package %1").arg(detail || target) : Tr.tr("AUR package %1").arg(detail || target);
            const rm = root.extraRmPath(extra ?? "");
            if (rm)
                return label + "\n" + Tr.tr("Also removes launcher file:\n%1").arg(rm);
            return label;
        }
        if (kind === "flatpak-user")
            return Tr.tr("Flatpak %1 (user)").arg(detail || target);
        if (kind === "flatpak-system")
            return Tr.tr("Flatpak %1 (system)").arg(detail || target);
        if (kind === "home-binary")
            return Tr.tr("Local files:\n%1").arg(root.extraTrashPath(extra) || target);
        if (kind === "prefix-game")
            return Tr.tr("Wine game folder:\n%1").arg(root.extraTrashPath(extra) || target);
        if (kind === "user") {
            const bin = root.extraBinInfo(extra ?? "");
            if (bin)
                return Tr.tr("Launcher entry only\nProgram: %1 (%2)").arg(bin.path).arg(root.describeOwner(bin.owner));
            return Tr.tr("Launcher entry only (no package)");
        }
        if (kind === "system-entry")
            return Tr.tr("Stale launcher file (no program found):\n%1").arg(target);
        return "";
    }

    function describeOwner(owner: string): string {
        if (!owner)
            return Tr.tr("unknown");
        if (owner === "unmanaged")
            return Tr.tr("not managed — remove manually");
        if (owner.startsWith("protected:"))
            return Tr.tr("system component");
        return Tr.tr("pacman: %1").arg(owner);
    }

    // Fire-and-confirm path for the `uninstall` action (already confirmed).
    function doRemove(entry: var, report: var): void {
        const rep = report ?? ((info) => root.toast(info.title ?? "", info.message ?? "", info.icon ?? "delete", info.type === "success" ? Toast.Success : info.type === "error" ? Toast.Error : Toast.Info));
        const name = entry?.name ?? entry?.id ?? Tr.tr("application");
        root.resolve(entry, (kind, target, detail, extra) => {
            if (!kind || kind === "none") {
                rep({ title: Tr.tr("Cannot uninstall %1").arg(name), message: root.cannotMessage(detail, extra), icon: "error", type: "error" });
                return;
            }
            root._report = rep;
            root._appName = name;
            root._kind = kind;
            root._target = target;
            root._detail = detail;
            root._extra = extra ?? "";
            root._pendingRm = (kind === "pacman" || kind === "aur") ? root.extraRmPath(root._extra) : "";
            root.runRemover(root.removerArgv(kind, target, root._extra));
        });
    }

    // Confirm a removal from an already-resolved target. Used by the
    // detail panel (which resolves lazily for display) and by request()
    // below. Note: no resolver.running check here — resolve callbacks fire
    // while the resolver is still spinning down.
    function requestResolved(kind: string, target: string, detail: string, extra: string, appName: var, list: var): void {
        const name = appName ?? Tr.tr("application");
        if (!kind || kind === "none") {
            root.toast(Tr.tr("Cannot uninstall %1").arg(name), root.cannotMessage(detail, extra), "error", Toast.Error);
            return;
        }
        if (root.pendingConfirm || remover.running) {
            root.notifyBusy();
            return;
        }
        root._pendingRm = (kind === "pacman" || kind === "aur") ? root.extraRmPath(extra ?? "") : "";
        root._entry = null;
        root._list = list ?? null;
        root._report = null;
        root._appName = name;
        root._kind = kind;
        root._target = target;
        root._detail = detail;
        root._extra = extra ?? "";
        root._removerArgv = root.removerArgv(kind, target, root._extra);
        root.pendingConfirm = {
            title: Tr.tr("Uninstall \"%1\"?\n%2").arg(name).arg(root.describeTarget(kind, target, detail, root._extra)),
            accept: Tr.tr("Uninstall")
        };
    }

    // Right-click path: resolve, then ask with the package named.
    function request(entry: var, list: var): void {
        if (root.pendingConfirm || remover.running || resolver.running) {
            root.notifyBusy();
            return;
        }
        const name = entry?.name ?? entry?.id ?? Tr.tr("application");
        root.resolve(entry, (kind, target, detail, extra) => {
            root.requestResolved(kind, target, detail, extra, name, list);
        });
    }

    // Multi-select for batch actions is tracked in Apps (entries, not
    // ids, so batch ops survive list refiltering). Batch uninstall lives
    // here: resolves run sequentially (single-flight resolver), one
    // confirm names every app, then removers run back to back with the
    // usual per-app toasts. Dismissed auth aborts the rest of the queue.
    property var _batch: []
    property var _batchResolved: []
    property bool _batchConfirm: false
    property var _batchList: null

    function startBatch(entries: var, list: var): void {
        const items = (entries ?? []).filter(e => e?.id);
        if (items.length === 0)
            return;
        if (root.pendingConfirm || remover.running || resolver.running || root._batch.length > 0) {
            root.notifyBusy();
            return;
        }
        root.closePanel();
        root._batch = [...items];
        root._batchResolved = [];
        root._batchConfirm = false;
        root._batchList = list ?? null;
        root._resolveNextBatch();
    }

    function _resolveNextBatch(): void {
        if (root._batch.length === 0) {
            if (root._batchResolved.length === 0)
                return; // nothing resolvable; per-app toasts already shown
            const names = root._batchResolved.map(r => r.name).join(", ");
            root._pendingRm = "";
            root._entry = null;
            root._list = root._batchList;
            root._report = null;
            root._batchConfirm = true;
            root.pendingConfirm = {
                title: Tr.trN("Uninstall %n app?", "Uninstall %n apps?", root._batchResolved.length) + "\n" + names,
                accept: Tr.tr("Uninstall all")
            };
            return;
        }
        const entry = root._batch[0];
        const name = entry?.name ?? entry?.id ?? Tr.tr("application");
        const started = root.resolve(entry, (kind, target, detail, extra) => {
            root._batch = root._batch.slice(1);
            if (!kind || kind === "none")
                root.toast(Tr.tr("Cannot uninstall %1").arg(name), root.cannotMessage(detail, extra), "error", Toast.Error);
            else
                root._batchResolved.push({ name: name, kind: kind, target: target, detail: detail, extra: extra ?? "" });
            root._resolveNextBatch();
        });
        if (!started) {
            root._batch = [];
            root._batchResolved = [];
            root._batchConfirm = false;
            root._batchList = null;
        }
    }

    function _runNextBatch(): void {
        const next = root._batchResolved[0];
        if (!next)
            return;
        root._batchResolved = root._batchResolved.slice(1);
        root._report = null; // default toast path, one toast per app
        root._appName = next.name;
        root._kind = next.kind;
        root._target = next.target;
        root._detail = next.detail;
        root._extra = next.extra;
        root._pendingRm = (next.kind === "pacman" || next.kind === "aur") ? root.extraRmPath(next.extra) : "";
        root._rmStage = false;
        root.runRemover(root.removerArgv(next.kind, next.target, next.extra));
    }

    function cancel(): void {
        root.pendingConfirm = null;
        root._entry = null;
        root._list = null;
        root._report = null;
        root._removerArgv = [];
        root._pendingRm = "";
        root._rmStage = false;
        root._batch = [];
        root._batchResolved = [];
        root._batchConfirm = false;
        root._batchList = null;
    }

    function accept(): void {
        if (root._batchConfirm) {
            root._batchConfirm = false;
            root.pendingConfirm = null;
            root.closePanel();
            const list = root._batchList;
            root._batchList = null;
            root._runNextBatch();
            // list is normally the AppList; accept a bare ScreenState too.
            if (list?.screenState)
                list.screenState.launcher = false;
            else if (list && list.launcher !== undefined)
                list.launcher = false;
            return;
        }
        const argv = root._removerArgv;
        const list = root._list;
        root.closePanel();
        root.pendingConfirm = null;
        root._entry = null;
        root._list = null;
        root._removerArgv = [];
        // Keep the report path so toasts still work without a list.
        root.runRemover(argv);
        // list is normally the AppList; accept a bare ScreenState too.
        if (list?.screenState)
            list.screenState.launcher = false;
        else if (list && list.launcher !== undefined)
            list.launcher = false;
    }

    function runRemover(argv: var): void {
        if (!argv || argv.length === 0) {
            const rep = root._report;
            const msg = { title: Tr.tr("Cannot uninstall"), message: "", icon: "error", type: "error" };
            if (rep)
                rep(msg);
            else
                root.toast(msg.title, msg.message, msg.icon, Toast.Error);
            root._report = null;
            return;
        }
        if (remover.running) {
            root.notifyBusy();
            return;
        }
        root._removerStderr = "";
        remover.command = argv;
        remover.running = true;
    }

    property Process remover: Process {
        stderr: StdioCollector {
            onStreamFinished: root._removerStderr = text;
        }
        onExited: (code, status) => {
            // Second stage: remove the leftover loose launcher file now that
            // its package is gone. State (report, names) is kept for the
            // final toast below.
            if (code === 0 && !root._rmStage && root._pendingRm !== "") {
                const rmPath = root._pendingRm;
                root._pendingRm = "";
                root._rmStage = true;
                root._removerStderr = "";
                remover.command = ["pkexec", "rm", "-f", rmPath];
                remover.running = true;
                return;
            }
            const rep = root._report;
            root._report = null;
            const name = root._appName;
            const kind = root._kind;
            const target = root._target;
            const second = root.extraTrashPath(root._extra);
            const rmDone = root._rmStage;
            const errTail = (root._removerStderr ?? "").split("\n").map(l => l.trim()).filter(l => l !== "").slice(-2).join(" ").slice(0, 160);
            root._appName = "";
            root._kind = "";
            root._target = "";
            root._detail = "";
            root._extra = "";
            root._removerStderr = "";
            root._pendingRm = "";
            root._rmStage = false;
            const done = (info) => {
                if (rep)
                    rep(info);
                else
                    root.toast(info.title ?? "", info.message ?? "", info.icon ?? "delete", info.type === "success" ? Toast.Success : info.type === "error" ? Toast.Error : Toast.Info);
            };
            if (code === 0) {
                let what = target;
                if (kind === "user")
                    what = Tr.tr("Removed launcher entry");
                else if (second)
                    what = Tr.tr("%1 + %2").arg(target).arg(second);
                else if (rmDone)
                    what = Tr.tr("%1 + launcher file").arg(target);
                done({ title: Tr.tr("Uninstalled %1").arg(name), message: what, icon: "delete", type: "success" });
            } else {
                // pkexec returns 126/127 when the auth dialog is dismissed.
                const cancelled = (kind === "pacman" || kind === "aur" || kind === "flatpak-system" || kind === "system-entry") && (code === 126 || code === 127);
                if (cancelled) {
                    root._batchResolved = []; // auth dismissed: stop the queue
                    done({ title: Tr.tr("Uninstall cancelled"), message: name, icon: "info", type: "warning" });
                } else if (rmDone)
                    done({ title: Tr.tr("Package removed, launcher file remains"), message: errTail || target, icon: "warning", type: "warning" });
                else if (errTail)
                    done({ title: Tr.tr("Uninstall failed: %1").arg(name), message: errTail, icon: "error", type: "error" });
                else
                    done({ title: Tr.tr("Uninstall failed"), message: Tr.tr("%1 (exit %2)").arg(name).arg(code), icon: "error", type: "error" });
            }
            // Batch queue: keep removing back to back after this app's toast.
            if (root._batchResolved.length > 0)
                root._runNextBatch();
        }
    }
}
