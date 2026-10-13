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

// Translate mini-app. The launcher morphs into this view when the
// `/translate` action is selected; Escape morphs back to the action list.
// Only translates on explicit action (button / Ctrl+Enter) - never on every
// keystroke - so no network traffic happens while typing.
Item {
    id: root

    required property var screenState
    required property SearchBar search

    signal closeRequested

    // Which language picker is expanded: "" (none), "source" or "target".
    property string openPicker: ""

    // Auto-copy guard: every successful translation lands in the clipboard
    // exactly once, no matter which flow produced it (one-shot command,
    // explicit button/Ctrl+Enter here, swap, provider cycle). The guard
    // prevents re-copying the same result on unrelated property churn.
    property string _lastAutoCopied: ""

    Connections {
        target: TranslateService

        function onResultChanged(): void {
            if (!TranslateService.translating && !TranslateService.error
                && TranslateService.result !== ""
                && TranslateService.result !== root._lastAutoCopied) {
                root._lastAutoCopied = TranslateService.result;
                Quickshell.clipboardText = TranslateService.result;
            }
        }
    }

    function backToActions(): void {
        TranslateService.clear();
        Actions.closeMiniApp();
        search.text = GlobalConfig.launcher.actionPrefix;
        search.forceActiveFocus();
        closeRequested();
    }

    function pickLanguage(code: string): void {
        if (openPicker === "source")
            TranslateService.sourceCode = code;
        else if (openPicker === "target" && code !== "auto")
            TranslateService.targetCode = code;
        TranslateService.error = "";
        openPicker = "";
        // Keep the flow going when there is already text to translate.
        if (TranslateService.input.trim())
            TranslateService.translate();
        else
            inputField.forceActiveFocus();
    }

    implicitWidth: Tokens.sizes.launcher.itemWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right

        spacing: Tokens.spacing.small

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "translate"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.large
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: Tr.tr("Translate")
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
            }

            StyledText {
                visible: !!TranslateService.detectedSource
                text: Tr.tr("Detected: %1").arg(TranslateService.detectedSource)
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
                Layout.alignment: Qt.AlignVCenter
            }

            // Engine: tap to cycle MyMemory → Google → Offline.
            TextButton {
                text: TranslateService.providerName
                type: TextButton.Tonal
                font: Tokens.font.label.small
                Layout.alignment: Qt.AlignVCenter
                onClicked: TranslateService.cycleProvider()
            }

            IconButton {
                icon: "close"
                type: IconButton.Text
                onClicked: root.backToActions()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Language selection: tap a language to open the full list, pick
        // one, and the list collapses. Swap button in the middle.
        // Keyboard: Tab reaches the buttons, Enter opens/picks,
        // Ctrl+Shift+S swaps, Escape goes back to the action list.
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            TextButton {
                text: TranslateService.sourceName
                type: TextButton.Tonal
                font: Tokens.font.label.medium
                Layout.fillWidth: true
                onClicked: root.openPicker = root.openPicker === "source" ? "" : "source"
            }

            IconButton {
                icon: "swap_horiz"
                type: IconButton.Text
                onClicked: {
                    TranslateService.swap();
                    inputField.text = TranslateService.input;
                }
                Layout.alignment: Qt.AlignVCenter
            }

            TextButton {
                text: TranslateService.targetName
                type: TextButton.Tonal
                font: Tokens.font.label.medium
                Layout.fillWidth: true
                onClicked: root.openPicker = root.openPicker === "target" ? "" : "target"
            }
        }

        // Language picker: full list instead of click-to-cycle, so every
        // language is visible and one tap away.
        StyledRect {
            visible: root.openPicker !== ""
            Layout.fillWidth: true
            implicitHeight: Math.min(pickerFlick.contentHeight, 220)
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            Behavior on implicitHeight {
                Anim {}
            }

            Flickable {
                id: pickerFlick

                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                clip: true
                contentHeight: pickerCol.implicitHeight
                flickableDirection: Flickable.VerticalFlick

                ColumnLayout {
                    id: pickerCol

                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 0

                    Repeater {
                        model: TranslateService.languages.filter(l => root.openPicker !== "target" || l.code !== "auto")

                        delegate: Item {
                            id: langItem

                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitHeight: Tokens.sizes.launcher.itemHeight * 0.72

                            readonly property bool isCurrent: root.openPicker === "source" ? modelData.code === TranslateService.sourceCode : modelData.code === TranslateService.targetCode

                            StateLayer {
                                radius: Tokens.rounding.medium
                                onClicked: root.pickLanguage(langItem.modelData.code)
                            }

                            StyledText {
                                anchors.left: parent.left
                                anchors.right: checkIcon.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Tokens.padding.medium
                                anchors.rightMargin: Tokens.spacing.small

                                text: langItem.modelData.name
                                font: Tokens.font.body.medium
                                color: langItem.isCurrent ? Colours.palette.m3primary : Colours.palette.m3onSurface
                                elide: Text.ElideRight
                            }

                            MaterialIcon {
                                id: checkIcon

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: Tokens.padding.medium

                                visible: langItem.isCurrent
                                text: "check"
                                color: Colours.palette.m3primary
                                fontStyle: Tokens.font.icon.medium
                            }
                        }
                    }
                }
            }
        }

        // Input
        StyledTextField {
            id: inputField

            Layout.fillWidth: true
            placeholderText: Tr.tr("Type or paste text...")
            onAccepted: {
                TranslateService.input = text;
                TranslateService.translate();
            }
            onTextEdited: TranslateService.input = text

            Keys.onPressed: event => {
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Return || (event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Enter) {
                    TranslateService.input = text;
                    TranslateService.translate();
                    event.accepted = true;
                } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_S) {
                    TranslateService.swap();
                    inputField.text = TranslateService.input;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    if (root.openPicker !== "")
                        root.openPicker = "";
                    else
                        root.backToActions();
                    event.accepted = true;
                }
            }
        }

        // Result
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: Math.max(resultText.implicitHeight + Tokens.padding.medium * 2, Tokens.sizes.launcher.itemHeight * 0.9)
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            StyledText {
                id: resultText

                anchors.left: parent.left
                anchors.right: copyButton.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.spacing.small

                text: {
                    if (TranslateService.translating)
                        return Tr.tr("Translating...");
                    if (TranslateService.error && !TranslateService.result)
                        return TranslateService.error;
                    if (TranslateService.result)
                        return TranslateService.result;
                    return Tr.tr("Translation appears here");
                }
                color: {
                    if (TranslateService.translating || (!TranslateService.result && !TranslateService.error))
                        return Colours.palette.m3onSurfaceVariant;
                    if (TranslateService.error && !TranslateService.result)
                        return Colours.palette.m3error;
                    return Colours.palette.m3onSurface;
                }
                font: Tokens.font.body.medium
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 4

                opacity: 1
                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
                onTextChanged: {
                    opacity = 0.2;
                    fadeBack.restart();
                }

                Timer {
                    id: fadeBack

                    interval: 120
                    onTriggered: resultText.opacity = 1
                }
            }

            IconButton {
                id: copyButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Tokens.padding.small

                icon: "content_copy"
                type: IconButton.Text
                enabled: !!TranslateService.result
                stateLayer.hoverEnabled: enabled
                opacity: enabled ? 1 : 0.35
                onClicked: TranslateService.copyResult()

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            Behavior on implicitHeight {
                Anim {}
            }
        }

        // Actions
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            TextButton {
                text: TranslateService.translating ? Tr.tr("Translating...") : Tr.tr("Translate")
                type: TextButton.Filled
                enabled: !TranslateService.translating && !!inputField.text.trim()
                Layout.fillWidth: true
                onClicked: {
                    TranslateService.input = inputField.text;
                    TranslateService.translate();
                }
            }

            TextButton {
                text: Tr.tr("Swap")
                type: TextButton.Text
                onClicked: {
                    TranslateService.swap();
                    inputField.text = TranslateService.input;
                }
            }

            TextButton {
                text: Tr.tr("Clear")
                type: TextButton.Text
                onClicked: {
                    TranslateService.clear();
                    inputField.text = "";
                    inputField.forceActiveFocus();
                }
            }
        }

        // History (bounded, persisted by the service)
        ColumnLayout {
            visible: TranslateService.history.length > 0
            spacing: Tokens.spacing.extraSmall
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    text: Tr.tr("Recent")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3outline
                    Layout.fillWidth: true
                }

                TextButton {
                    text: Tr.tr("Clear history")
                    type: TextButton.Text
                    font: Tokens.font.label.small
                    onClicked: TranslateService.clearHistory()
                }
            }

            Repeater {
                model: TranslateService.history.slice(0, 5)

                delegate: Item {
                    id: historyItem

                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: historyCol.implicitHeight + Tokens.padding.small * 2

                    StateLayer {
                        radius: Tokens.rounding.medium
                        onClicked: {
                            TranslateService.input = historyItem.modelData.input;
                            inputField.text = historyItem.modelData.input;
                            TranslateService.result = historyItem.modelData.output;
                            inputField.forceActiveFocus();
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
                            text: historyItem.modelData.input
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: `→ ${historyItem.modelData.output}`
                            font: Tokens.font.body.small
                            color: Colours.palette.m3outline
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        // Prefill from `/translate <text>` and go straight to translating.
        const initial = Actions.miniAppInitialText || TranslateService.input;
        if (initial) {
            inputField.text = initial;
            TranslateService.input = initial;
            TranslateService.translate();
        } else {
            inputField.forceActiveFocus();
        }
    }
}
