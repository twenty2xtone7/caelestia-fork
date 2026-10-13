pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services
import qs.modules.launcher
import qs.modules.launcher.items

Item {
    id: root

    required property ScreenState screenState
    required property var panels
    required property real maxHeight

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: LiquidGlass.enabled ? LiquidGlass.cornerRadius : Tokens.rounding.extraLarge

    readonly property bool inTranslateMode: Actions.activeMiniApp === "translate"
    readonly property bool inMusicMode: Actions.activeMiniApp === "music"
    readonly property bool inFanMode: Actions.activeMiniApp === "fan"
    readonly property bool inNightMode: Actions.activeMiniApp === "night"
    readonly property bool inClipboardMode: Actions.activeMiniApp === "clipboard" || ClipboardService.open

    // Space for the app detail side panel. Kept out of listWrapper on
    // purpose: ContentList stretches to its parent's width, so counting the
    // panel inside listWrapper would feed back into the list width (binding
    // loop). The slot width only depends on panelOpen, a plain bool.
    readonly property int detailWidth: Math.round(Tokens.sizes.launcher.itemWidth * 0.5)

    implicitWidth: listWrapper.width + padding * 2 + (detailSlot.width > 0 ? detailSlot.width + padding : 0)
    implicitHeight: search.height + listWrapper.height + padding + search.anchors.bottomMargin

    CommandConfirmDialog {
        id: confirmDialog

        onClosed: search.forceActiveFocus()
    }

    Item {
        id: listWrapper

        implicitWidth: list.width
        implicitHeight: list.height + root.padding

        // Left-anchored (not centered) so the list never moves when the
        // detail panel expands to the right; the window grows rightward
        // only. Closed state looks identical because the content width
        // fits exactly.
        anchors.left: parent.left
        anchors.leftMargin: root.padding
        anchors.bottom: search.top
        anchors.bottomMargin: root.padding

        ContentList {
            id: list

            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight - search.implicitHeight - root.padding * 3
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }

    // Expandable panel directly right of the app list. The window grows
    // rightward with it (see implicitWidth above) while the list stays
    // put. Aligned to the list itself so the rows line up exactly.
    Item {
        id: detailSlot

        anchors.left: listWrapper.right
        anchors.leftMargin: Uninstall.panelOpen ? root.padding : 0
        // Aligned with the list rows: the list sits at the bottom of
        // listWrapper with `padding` breathing room above it.
        anchors.top: listWrapper.top
        anchors.topMargin: root.padding
        anchors.bottom: listWrapper.bottom

        width: Uninstall.panelOpen ? root.detailWidth : 0
        clip: true

        Behavior on width {
            NumberAnimation { duration: 420; easing.type: Easing.OutQuint }
        }

        Behavior on anchors.leftMargin {
            NumberAnimation { duration: 420; easing.type: Easing.OutQuint }
        }

        Loader {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: root.detailWidth

            active: Uninstall.panelOpen || detailSlot.width > 0.5
            opacity: Uninstall.panelOpen ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 360; easing.type: Easing.OutQuint }
            }

            sourceComponent: AppDetailPanel {
                // Follows the highlighted app while open; falls back to the
                // pinned entry when the selection isn't an app (e.g. a
                // typed command result).
                entry: {
                    const d = list.currentList?.currentItem?.modelData;
                    return (d && !d.__command && d.id) ? d : Uninstall.panelEntry;
                }
                // Pinned list first: it always carries screenState for
                // closing; the live list may be a view without one.
                list: Uninstall.panelList ?? list.currentList
            }
        }
    }

    SearchBar {
        id: search

        objectName: "launcherSearch"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.bottomMargin: CUtils.clamp(root.padding - Config.border.thickness, 0, root.padding)

        topPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)
        bottomPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)

        placeholderText: {
            if (root.inTranslateMode)
                return Tr.tr("Translate mode — Escape to go back");
            if (root.inMusicMode)
                return Tr.tr("Music mode — Escape to go back");
            if (root.inFanMode)
                return Tr.tr("Fan mode — arrows/wheel adjust, Escape to go back");
            if (root.inNightMode)
                return Tr.tr("Night mode — adjust intensity, Escape to go back");
            if (root.inClipboardMode)
                return ClipboardService.deleteMode ? Tr.tr("Delete mode — Enter deletes, Escape goes back") : Tr.tr("Search clipboard — Tab previews, Enter copies, Escape goes back");
            return Tr.tr("Type \"%1\" for actions").arg(GlobalConfig.launcher.actionPrefix);
        }

        // Mode indicator: the search icon morphs with the mode instead of
        // the UI being swapped out.
        searchIcon.text: root.inTranslateMode ? "translate" : root.inMusicMode ? "music_note" : root.inFanMode ? "mode_fan" : root.inNightMode ? "nightlight" : root.inClipboardMode ? "content_paste" : "search"
        searchIcon.color: root.inTranslateMode || root.inFanMode || root.inNightMode || root.inClipboardMode ? Colours.palette.m3primary : root.inMusicMode ? Colours.palette.m3secondary : Colours.palette.m3onSurfaceVariant

        onAccepted: {
            if (CommandRegistry.pendingConfirm) {
                CommandRegistry.acceptPending();
                return;
            }
            if (Uninstall.pendingConfirm) {
                confirmDialog.accept();
                return;
            }
            // Translate/music/fan/night keep their own inputs; clipboard filters from here.
            if (root.inTranslateMode || root.inMusicMode || root.inFanMode || root.inNightMode)
                return;
            if (root.inClipboardMode) {
                const entry = list.currentList?.currentItem?.modelData;
                if (!entry)
                    return;
                if (ClipboardService.deleteMode)
                    ClipboardService.remove(entry);
                else {
                    ClipboardService.copy(entry);
                    root.screenState.launcher = false;
                }
                return;
            }
            const currentItem = list.currentList?.currentItem;
            if (currentItem) {
                if (list.showWallpapers) {
                    if (Colours.scheme === "dynamic" && currentItem.modelData.path !== Wallpapers.actualCurrent)
                        Wallpapers.previewColourLock = true;
                    Wallpapers.setWallpaper(currentItem.modelData.path);
                    root.screenState.launcher = false;
                } else if (text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                    if (text.startsWith(`${GlobalConfig.launcher.actionPrefix}calc `))
                        currentItem.onClicked();
                    else
                        currentItem.modelData.onClicked(list.currentList);
                } else if (currentItem.modelData?.__command) {
                    // Universal Action Launcher command result in app-search
                    // state; activate it directly instead of treating it as a
                    // DesktopEntry.
                    currentItem.modelData.onClicked(list.currentList);
                } else {
                    Apps.launch(currentItem.modelData);
                    root.screenState.launcher = false;
                }
            }
        }

        Keys.onUpPressed: list.currentList?.decrementCurrentIndex()
        Keys.onDownPressed: list.currentList?.incrementCurrentIndex()

        // Right opens the detail panel for the highlighted app (delete and
        // friends live there). Only hijacked at end-of-line so cursor
        // movement while editing still works.
        Keys.onRightPressed: event => {
            if (search.cursorPosition !== search.text.length)
                return;
            if (root.inTranslateMode || root.inMusicMode || root.inFanMode || root.inNightMode || root.inClipboardMode || text.startsWith(GlobalConfig.launcher.actionPrefix))
                return;
            const data = list.currentList?.currentItem?.modelData;
            if (data && !data.__command && data.id) {
                Uninstall.openPanel(data, list.currentList);
                event.accepted = true;
            }
        }

        // Left backs out of the panel; otherwise moves the cursor as usual.
        Keys.onLeftPressed: event => {
            if (Uninstall.panelOpen) {
                Uninstall.closePanel();
                event.accepted = true;
            }
        }

        Keys.onEscapePressed: {
            if (CommandRegistry.pendingConfirm) {
                CommandRegistry.cancelPending();
                return;
            }
            if (Uninstall.pendingConfirm) {
                confirmDialog.cancel();
                return;
            }
            if (Uninstall.panelOpen) {
                Uninstall.closePanel();
                return;
            }
            // Mini-app Escape is handled by the mini-app itself (back to the
            // action list). Here Escape closes, matching existing behavior.
            if (root.inClipboardMode) {
                if (list.collapseClipboardPreview())
                    return;
                const fromAction = Actions.activeMiniApp === "clipboard";
                ClipboardService.open = false;
                ClipboardService.deleteMode = false;
                Actions.closeMiniApp();
                if (fromAction) {
                    text = GlobalConfig.launcher.actionPrefix;
                    forceActiveFocus();
                } else {
                    root.screenState.launcher = false;
                }
            } else if (!root.inTranslateMode && !root.inMusicMusic) {
                root.screenState.launcher = false;
            }
        }

        Keys.onPressed: event => {
            // Tab toggles the expanded image preview in clipboard mode
            // (arrows/Enter keep working; Escape collapses).
            if (root.inClipboardMode && event.key === Qt.Key_Tab) {
                if (list.toggleClipboardPreview())
                    event.accepted = true;
                return;
            }
            // Ctrl+Enter uninstalls the highlighted app (same confirm flow
            // as the row's trash button / right-click). Plain Enter still
            // launches. Guarded to plain app search so text editing and
            // mini-app inputs are untouched.
            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                if (!root.inTranslateMode && !root.inMusicMode && !root.inFanMode && !root.inNightMode && !root.inClipboardMode && !text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                    const data = list.currentList?.currentItem?.modelData;
                    if (data && !data.__command && data.id) {
                        Uninstall.request(data, list.currentList);
                        event.accepted = true;
                        return;
                    }
                }
            }
            if (!GlobalConfig.launcher.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab) {
                list.currentList?.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                list.currentList?.decrementCurrentIndex();
                event.accepted = true;
            }
        }

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (root.screenState.launcher) {
                    // Re-probe the fan backend: the kernel module may have
                    // been (re)loaded after the shell started.
                    FanCtl.reload();
                }
                if (!root.screenState.launcher) {
                    // Remember mid-task music state so reopening restores it.
                    // Escaping to the action list first (or leaving music
                    // empty) means a fresh open, as before.
                    MusicService.leftInMusic = Actions.activeMiniApp === "music" && (MusicService.savedQuery !== "" || MusicService.searching || MusicService.results.length > 0);
                    Uninstall.closePanel();
                    search.text = "";
                    ClipboardService.open = false;
                    ClipboardService.deleteMode = false;
                    Actions.closeMiniApp();
                } else if (MusicService.leftInMusic) {
                    MusicService.leftInMusic = false;
                    Actions.openMiniApp("music", MusicService.savedQuery);
                }
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    search.forceActiveFocus();
            }

            target: root.screenState
        }
    }
}
