pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

// Ask-AI mini-app. The launcher morphs into this view when the `chat`
// command result is selected; Escape or the X button morphs back. Free
// backend (Pollinations, no key); responses arrive whole, not streamed.
Item {
    id: root

    required property var screenState
    required property SearchBar search

    signal closeRequested

    focus: true

    function backToActions(): void {
        ChatService.clear();
        Actions.closeMiniApp();
        search.text = GlobalConfig.launcher.actionPrefix;
        search.forceActiveFocus();
        closeRequested();
    }

    function askCurrent(): void {
        ChatService.ask(inputField.text);
    }

    implicitWidth: Tokens.sizes.launcher.itemWidth * 1.3
    implicitHeight: layout.implicitHeight

    Component.onCompleted: {
        // Prefill from `chat <question>` and ask straight away.
        const initial = Actions.miniAppInitialText || ChatService.input;
        if (initial) {
            inputField.text = initial;
            ChatService.ask(initial);
        } else {
            inputField.forceActiveFocus();
        }
    }

    Keys.onEscapePressed: backToActions()

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right

        spacing: Tokens.spacing.medium

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "smart_toy"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.large
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Tr.tr("Ask AI")
                    font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                    elide: Text.ElideRight
                }

                StyledText {
                    text: Tr.tr("Free · answers may be wrong")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3outline
                    elide: Text.ElideRight
                }
            }

            IconButton {
                icon: "close"
                type: IconButton.Text
                onClicked: root.backToActions()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Input
        StyledTextField {
            id: inputField

            Layout.fillWidth: true
            placeholderText: Tr.tr("Ask anything...")
            onAccepted: root.askCurrent()
            onTextEdited: ChatService.input = text

            Keys.onPressed: event => {
                if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                    root.askCurrent();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.backToActions();
                    event.accepted = true;
                }
            }
        }

        // Response
        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(300, Math.max(responseText.implicitHeight + Tokens.padding.medium * 2, Tokens.sizes.launcher.itemHeight * 0.9))
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            Flickable {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                clip: true
                contentHeight: responseText.implicitHeight
                flickableDirection: Flickable.VerticalFlick

                StyledText {
                    id: responseText

                    width: parent.width
                    text: {
                        if (ChatService.asking)
                            return Tr.tr("Thinking...");
                        if (ChatService.error && !ChatService.response)
                            return ChatService.error;
                        if (ChatService.response)
                            return ChatService.response;
                        return Tr.tr("The answer appears here");
                    }
                    color: ChatService.error && !ChatService.response ? Colours.palette.m3error : Colours.palette.m3onSurface
                    opacity: ChatService.response || ChatService.error ? 1 : 0.6
                    font: Tokens.font.body.medium
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
            }

            IconButton {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Tokens.padding.small

                icon: "content_copy"
                type: IconButton.Text
                enabled: !!ChatService.response
                opacity: enabled ? 1 : 0.35
                onClicked: Quickshell.clipboardText = ChatService.response

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }

        // Actions
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            TextButton {
                text: ChatService.asking ? Tr.tr("Thinking...") : Tr.tr("Ask")
                type: TextButton.Filled
                enabled: !ChatService.asking && !!inputField.text.trim()
                Layout.fillWidth: true
                onClicked: root.askCurrent()
            }

            TextButton {
                text: Tr.tr("Clear")
                type: TextButton.Text
                onClicked: {
                    ChatService.clear();
                    ChatService.clearHistory();
                    inputField.text = "";
                    inputField.forceActiveFocus();
                }
            }
        }

        // Recent
        ColumnLayout {
            visible: ChatService.history.length > 0
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: Tr.tr("Recent")
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
            }

            Repeater {
                model: ChatService.history.slice(0, 5)

                delegate: Item {
                    id: historyItem

                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: historyCol.implicitHeight + Tokens.padding.small * 2

                    StateLayer {
                        radius: Tokens.rounding.medium
                        onClicked: {
                            inputField.text = historyItem.modelData.q;
                            ChatService.input = historyItem.modelData.q;
                            root.askCurrent();
                        }
                    }

                    ColumnLayout {
                        id: historyCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: historyItem.modelData.q
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `→ ${(historyItem.modelData.a ?? "").slice(0, 120)}`
                            font: Tokens.font.body.small
                            color: Colours.palette.m3outline
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
