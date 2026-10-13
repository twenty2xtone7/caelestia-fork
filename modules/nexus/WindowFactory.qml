pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.modules.nexus
import qs.modules.launcher.services

Singleton {
    id: root

    // Index into PageRegistry.pages to open instead of the default
    // first page. Consumed (and reset) by the created window.
    property int startPage: 0

    // The live Nexus floating window, if any. Chat reuses it so `chat <prompt>`
    // can switch an already-open Settings window into AI Chat mode.
    property var instance: null

    function create(parent: Item, props: var): void {
        nexusComp.createObject(parent ?? dummy, props);
    }

    function growChatWindow(): void {
        if (!root.instance)
            return;
        root.instance.width = Math.max(root.instance.width, root.instance.implicitWidth);
        root.instance.height = Math.max(root.instance.height, root.instance.implicitHeight);
    }

    function openChat(prompt: string): void {
        const text = (prompt ?? "").trim();
        if (root.instance) {
            root.instance.nState.chatMode = true;
            root.instance.minimized = false;
            root.growChatWindow();
            root.focusInstance();
            if (text)
                ChatService.ask(text);
            return;
        }
        nexusComp.createObject(dummy, {
            startChatMode: true,
            startPrompt: text
        });
    }

    function exitChat(): void {
        if (root.instance)
            root.instance.nState.chatMode = false;
    }

    function focusInstance(): void {
        if (!root.instance)
            return;
        Hypr.dispatch("focuswindow title:^(Nexus)");
    }

    QtObject {
        id: dummy
    }

    Component {
        id: nexusComp

        FloatingWindow {
            id: win

            property bool startChatMode: false
            property string startPrompt: ""
            readonly property alias nState: nexus.nState

            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            onVisibleChanged: {
                if (!visible)
                    destroy();
            }

            implicitWidth: nexus.implicitWidth
            implicitHeight: nexus.implicitHeight

            minimumSize.width: contentItem.Tokens.sizes.nexus.minWidth
            minimumSize.height: contentItem.Tokens.sizes.nexus.minHeight

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            title: nexus.nState.chatMode ? Tr.tr("Nexus — AI Chat") : Tr.tr("Nexus — %1").arg(PageRegistry.pages[nexus.nState.currentPageIdx].label)

            Nexus {
                id: nexus

                anchors.fill: parent
                nState.screen: win.screen
                nState.isWindow: true
                onClose: win.destroy()

                Component.onCompleted: {
                    root.instance = win;
                    nState.currentPageIdx = root.startPage;
                    root.startPage = 0;
                    // Assign once. A binding back to startChatMode would snap
                    // chatMode true again if the user exits AI Chat.
                    nState.chatMode = win.startChatMode;
                    if (win.startChatMode && win.startPrompt)
                        ChatService.ask(win.startPrompt);
                }
            }

            Component.onDestruction: {
                if (root.instance === win)
                    root.instance = null;
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
