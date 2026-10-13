pragma Singleton

import ".."
import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.services
import qs.utils

Searcher {
    id: root

    function transformSearch(search: string): string {
        return search.slice(GlobalConfig.launcher.actionPrefix.length);
    }

    // Mini-app routing. Empty means "no mini-app active". `ContentList.qml`
    // binds to this to morph between the action list and mini-app views.
    // (This used to live on the removed `:` command provider; it stays a
    // single routing point now owned by `/` actions.)
    property string activeMiniApp: ""
    property string miniAppInitialText: ""

    function openMiniApp(appId: string, initialText: string): void {
        miniAppInitialText = initialText ?? "";
        activeMiniApp = appId;
    }

    function closeMiniApp(): void {
        activeMiniApp = "";
        miniAppInitialText = "";
    }

    // Translate mini-app entry. Lives here (under the `/` action prefix)
    // instead of the `:` command list, so `/translate`, `/trans`, `/tr`
    // — plus `/translate <text>` with prefilled input — open the translator.
    // The mini-app view state itself stays on `Commands` (shared routing used
    // by ContentList/Content/TranslateView); only the trigger moved.
    readonly property list<string> translateKeywords: ["translate", "trans", "translation", "language"]

    // Direct `/translate some text` support: everything after the command
    // word becomes the mini-app's initial input. Only full command words
    // prefill - a partial like `/tra` just filters the list.
    function translateRemainder(text: string): string {
        const inner = text.slice(GlobalConfig.launcher.actionPrefix.length).trim();
        const match = inner.match(/^(translation|translate|trans|tr)(?:\s+(.*))?\s*$/i);
        return match ? (match[2] ?? "").trim() : "";
    }

    function matchesTranslate(text: string): bool {
        const inner = transformSearch(text.trim().replace(/\s+/g, " ")).trim().toLowerCase();
        if (!inner)
            return true;
        const first = inner.split(" ")[0];
        return translateKeywords.some(k => k.startsWith(first));
    }

    // Pseudo-action with the same shape as `Action` so `ActionItem` and the
    // existing `onClicked(list)` dispatch work unchanged.
    readonly property QtObject translateAction: QtObject {
        readonly property string name: Tr.tr("Translate")
        readonly property string desc: Tr.tr("Translate text between languages")
        readonly property string icon: "translate"
        readonly property list<string> command: ["translate"]
        readonly property bool enabled: true
        readonly property bool dangerous: false

        function onClicked(list: var): void {
            root.openMiniApp("translate", root.translateRemainder(list.search.text));
        }
    }

    function translateMatches(text: string): var {
        return matchesTranslate(text) ? [translateAction] : [];
    }

    // Music mini-app entry. Same pattern as translate:
    // `/music`, `/mus` — plus `/music <query>` with prefilled input —
    // open the music searcher.
    readonly property list<string> musicKeywords: ["music", "mus"]

    // Direct `/music some query` support: everything after the command
    // word becomes the mini-app's initial input. Only full command words
    // prefill - a partial like `/mus` just filters the list.
    function musicRemainder(text: string): string {
        const inner = text.slice(GlobalConfig.launcher.actionPrefix.length).trim();
        const match = inner.match(/^(music|mus)(?:\s+(.*))?\s*$/i);
        return match ? (match[2] ?? "").trim() : "";
    }

    function matchesMusic(text: string): bool {
        const inner = transformSearch(text.trim().replace(/\s+/g, " ")).trim().toLowerCase();
        if (!inner)
            return true;
        const first = inner.split(" ")[0];
        return musicKeywords.some(k => k.startsWith(first));
    }

    // Pseudo-action with the same shape as `Action` so `ActionItem` and the
    // existing `onClicked(list)` dispatch work unchanged.
    readonly property QtObject musicAction: QtObject {
        readonly property string name: Tr.tr("Music")
        readonly property string desc: Tr.tr("Search and play music")
        readonly property string icon: "music_note"
        readonly property list<string> command: ["music"]
        readonly property bool enabled: true
        readonly property bool dangerous: false

        function onClicked(list: var): void {
            root.openMiniApp("music", root.musicRemainder(list.search.text));
        }
    }

    function musicMatches(text: string): var {
        return matchesMusic(text) ? [musicAction] : [];
    }

    readonly property list<string> clipboardKeywords: ["clipboard", "clip", "paste"]

    function clipboardRemainder(text: string): string {
        const inner = text.slice(GlobalConfig.launcher.actionPrefix.length).trim();
        const match = inner.match(/^(clipboard|clip|paste)(?:\s+(.*))?\s*$/i);
        return match ? (match[2] ?? "").trim() : "";
    }

    function matchesClipboard(text: string): bool {
        const inner = transformSearch(text.trim().replace(/\s+/g, " ")).trim().toLowerCase();
        if (!inner)
            return true;
        const first = inner.split(" ")[0];
        return clipboardKeywords.some(k => k.startsWith(first));
    }

    readonly property QtObject clipboardAction: QtObject {
        readonly property string name: Tr.tr("Clipboard")
        readonly property string desc: Tr.tr("Clipboard history with image preview")
        readonly property string icon: "content_paste"
        readonly property list<string> command: ["clipboard"]
        readonly property bool enabled: true
        readonly property bool dangerous: false

        function onClicked(list: var): void {
            ClipboardService.deleteMode = false;
            ClipboardService.open = true;
            ClipboardService.imagesReady = false;
            root.openMiniApp("clipboard", root.clipboardRemainder(list.search.text));
        }
    }

    function clipboardMatches(text: string): var {
        return matchesClipboard(text) ? [clipboardAction] : [];
    }

    list: variants.instances
    useFuzzy: GlobalConfig.launcher.useFuzzy.actions

    Variants {
        id: variants

        model: {
            const enableDangerous = GlobalConfig.launcher.enableDangerousActions;
            return GlobalConfig.launcher.actions.values.filter(a => a.enabled && (enableDangerous || !a.dangerous));
        }

        Action {}
    }

    component Action: QtObject {
        required property var modelData
        readonly property string name: modelData.name ? Tr.trMarked(modelData.name) : Tr.trCtx("Unnamed", "launcher action with no name")
        readonly property string desc: modelData.description ? Tr.trMarked(modelData.description) : Tr.trCtx("No description", "launcher action with no description")
        readonly property string icon: modelData.icon ?? "help_outline"
        readonly property list<string> command: modelData.command ?? []
        readonly property bool enabled: modelData.enabled ?? true
        readonly property bool dangerous: modelData.dangerous ?? false

        function onClicked(list: AppList): void {
            if (command.length === 0)
                return;

            if (command[0] === "autocomplete" && command.length > 1) {
                list.search.text = `${GlobalConfig.launcher.actionPrefix}${command[1]} `;
            } else if (command[0] === "setMode" && command.length > 1) {
                list.screenState.launcher = false;
                Colours.setMode(command[1]);
            } else {
                list.screenState.launcher = false;
                if (!SessionManager.exec(command))
                    Quickshell.execDetached(command);
            }
        }
    }
}
