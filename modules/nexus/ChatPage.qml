pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.nexus
import qs.modules.launcher.services

// Dedicated Nexus AI Chat mode. Sessions and requests live on ChatService,
// so closing this view does not stop a reply in progress.
Item {
    id: root

    required property NexusState nState

    focus: true
    property bool sessionsOpen: true

    readonly property int sessionWidth: Math.min(280, Math.max(200, Math.round(width * 0.24)))

    function exitChat(): void {
        WindowFactory.exitChat();
        root.nState.chatMode = false;
    }

    function sendCurrent(): void {
        const q = inputField.text.trim();
        if (!q || ChatService.asking)
            return;
        ChatService.ask(q);
        inputField.text = "";
        ChatService.input = "";
    }

    function newSession(): void {
        ChatService.createSession(true);
        inputField.text = "";
        inputField.forceActiveFocus();
    }

    function scrollToBottom(): void {
        if (transcript.contentHeight <= transcript.height)
            return;
        transcript.contentY = Math.max(0, transcript.contentHeight - transcript.height);
    }

    Component.onCompleted: {
        ChatService.restoreMessages();
        inputField.forceActiveFocus();
        Qt.callLater(root.scrollToBottom);
    }

    Keys.onEscapePressed: root.exitChat()

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.medium

        StyledRect {
            visible: root.sessionsOpen
            Layout.preferredWidth: root.sessionWidth
            Layout.fillHeight: true
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerLow

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Sessions")
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }

                    IconButton {
                        icon: "add"
                        type: IconButton.Tonal
                        onClicked: root.newSession()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Each session keeps its own conversation.")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.Wrap
                }

                VerticalFadeFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: sessionCol.implicitHeight

                    Column {
                        id: sessionCol

                        width: parent.width
                        spacing: Tokens.spacing.extraSmall

                        Repeater {
                            model: ChatService.sessions

                            delegate: Item {
                                id: sessionItem

                                required property var modelData
                                required property int index

                                readonly property bool current: modelData.id === ChatService.activeSessionId

                                width: sessionCol.width
                                height: sessionRow.implicitHeight + Tokens.padding.small * 2

                                StyledRect {
                                    anchors.fill: parent
                                    radius: Tokens.rounding.medium
                                    color: sessionItem.current ? Colours.palette.m3secondaryContainer : "transparent"
                                }

                                StateLayer {
                                    radius: Tokens.rounding.medium
                                    onClicked: ChatService.switchSession(sessionItem.modelData.id)
                                }

                                RowLayout {
                                    id: sessionRow

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Tokens.padding.medium
                                    anchors.rightMargin: Tokens.padding.small
                                    spacing: Tokens.spacing.small

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: sessionItem.modelData.title || Tr.tr("New chat")
                                            font: Tokens.font.body.medium
                                            color: sessionItem.current ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: (sessionItem.modelData.messages?.length ?? 0) > 0 ? Tr.tr("%1 messages").arg(sessionItem.modelData.messages.length) : Tr.tr("Empty")
                                            font: Tokens.font.label.small
                                            color: Colours.palette.m3outline
                                            elide: Text.ElideRight
                                        }
                                    }

                                    IconButton {
                                        icon: "close"
                                        type: IconButton.Text
                                        visible: ChatService.sessions.length > 1
                                        onClicked: ChatService.deleteSession(sessionItem.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                IconButton {
                    icon: "arrow_back"
                    type: IconButton.Tonal
                    isRound: true
                    inactiveColour: Colours.tPalette.m3surfaceContainerHigh
                    inactiveOnColour: Colours.palette.m3onSurfaceVariant
                    onClicked: root.exitChat()
                }

                IconButton {
                    icon: root.sessionsOpen ? "menu_open" : "menu"
                    type: IconButton.Text
                    onClicked: root.sessionsOpen = !root.sessionsOpen
                }

                MaterialIcon {
                    text: "smart_toy"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: ChatService.activeSession?.title || Tr.tr("AI Chat")
                        font: Tokens.font.title.large
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: ChatService.backendLabel
                        font: Tokens.font.body.small
                        color: Colours.palette.m3outline
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    icon: "add_comment"
                    type: IconButton.Text
                    onClicked: root.newSession()
                }

                IconButton {
                    icon: "delete"
                    type: IconButton.Text
                    enabled: ChatService.messages.length > 0
                    opacity: enabled ? 1 : 0.35
                    onClicked: {
                        ChatService.clearMessages();
                        inputField.text = "";
                        inputField.forceActiveFocus();
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                VerticalFadeFlickable {
                    id: transcript

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    clip: true
                    contentHeight: thread.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    onContentHeightChanged: scrollTimer.restart()
                    onHeightChanged: scrollTimer.restart()

                    ColumnLayout {
                        id: thread

                        width: transcript.width
                        spacing: Tokens.spacing.large

                        Item {
                            visible: ChatService.messages.length === 0 && !ChatService.streamingHere
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(emptyHint.implicitHeight + Tokens.padding.extraLarge * 2, transcript.height * 0.45)

                            ColumnLayout {
                                id: emptyHint

                                anchors.centerIn: parent
                                width: Math.min(parent.width * 0.7, 640)
                                spacing: Tokens.spacing.medium

                                MaterialIcon {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "forum"
                                    color: Colours.palette.m3primary
                                    fontStyle: Tokens.font.icon.extraLarge
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Tr.tr("Start a conversation")
                                    font: Tokens.font.headline.medium
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Tr.tr("Type below, or launch with chat <prompt>. Sessions stay saved, and a reply keeps going if you close this window.")
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.body.large
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        Repeater {
                            model: ChatService.messages

                            delegate: Item {
                                id: bubbleWrap

                                required property var modelData
                                required property int index

                                readonly property bool isUser: modelData.role === "user"
                                readonly property bool isError: modelData.role === "error"

                                Layout.fillWidth: true
                                implicitHeight: bubbleCol.implicitHeight

                                ColumnLayout {
                                    id: bubbleCol

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: Tokens.spacing.extraSmall

                                    StyledText {
                                        Layout.alignment: bubbleWrap.isUser ? Qt.AlignRight : Qt.AlignLeft
                                        Layout.leftMargin: Tokens.padding.small
                                        Layout.rightMargin: Tokens.padding.small
                                        text: bubbleWrap.isUser ? Tr.tr("You") : bubbleWrap.isError ? Tr.tr("Error") : Tr.tr("AI")
                                        font: Tokens.font.label.medium
                                        color: Colours.palette.m3outline
                                    }

                                    StyledRect {
                                        Layout.alignment: bubbleWrap.isUser ? Qt.AlignRight : Qt.AlignLeft
                                        Layout.maximumWidth: Math.min(thread.width * 0.78, 820)
                                        implicitWidth: Math.min(thread.width * 0.78, bubbleText.implicitWidth + Tokens.padding.largeIncreased * 2)
                                        implicitHeight: bubbleText.implicitHeight + Tokens.padding.large * 2
                                        radius: Tokens.rounding.extraLarge
                                        color: bubbleWrap.isError ? Qt.alpha(Colours.palette.m3error, 0.12) : bubbleWrap.isUser ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh

                                        StyledText {
                                            id: bubbleText

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: Tokens.padding.largeIncreased
                                            anchors.rightMargin: Tokens.padding.largeIncreased
                                            text: bubbleWrap.modelData.content || ""
                                            color: bubbleWrap.isError ? Colours.palette.m3error : bubbleWrap.isUser ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                            font: Tokens.font.body.large
                                            wrapMode: Text.Wrap
                                            textFormat: Text.PlainText
                                        }
                                    }

                                    IconButton {
                                        visible: !bubbleWrap.isUser && !bubbleWrap.isError && !!(bubbleWrap.modelData.content)
                                        icon: "content_copy"
                                        type: IconButton.Text
                                        onClicked: Quickshell.clipboardText = bubbleWrap.modelData.content ?? ""
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            visible: ChatService.streamingHere
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.extraSmall

                            StyledText {
                                Layout.leftMargin: Tokens.padding.small
                                text: Tr.tr("AI")
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3outline
                            }

                            StyledRect {
                                Layout.alignment: Qt.AlignLeft
                                Layout.maximumWidth: Math.min(thread.width * 0.78, 820)
                                implicitWidth: ChatService.response ? Math.min(thread.width * 0.78, liveText.implicitWidth + Tokens.padding.largeIncreased * 2) : liveRow.implicitWidth + Tokens.padding.large * 2
                                implicitHeight: (ChatService.response ? liveText.implicitHeight : liveRow.implicitHeight) + Tokens.padding.large * 2
                                radius: Tokens.rounding.extraLarge
                                color: Colours.tPalette.m3surfaceContainerHigh

                                RowLayout {
                                    id: liveRow

                                    visible: !ChatService.response
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Tokens.padding.large
                                    spacing: Tokens.spacing.small

                                    CircularIndicator {
                                        implicitSize: Tokens.font.body.large.pointSize * 1.6
                                        running: ChatService.streamingHere && !ChatService.response
                                    }

                                    StyledText {
                                        text: ChatService.status || Tr.tr("Thinking…")
                                        color: Colours.palette.m3outline
                                        font: Tokens.font.body.large
                                    }
                                }

                                StyledText {
                                    id: liveText

                                    visible: !!ChatService.response
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Tokens.padding.largeIncreased
                                    anchors.rightMargin: Tokens.padding.largeIncreased
                                    text: ChatService.response
                                    color: Colours.palette.m3onSurface
                                    font: Tokens.font.body.large
                                    wrapMode: Text.Wrap
                                    textFormat: Text.PlainText
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledTextField {
                    id: inputField

                    Layout.fillWidth: true
                    font: Tokens.font.body.large
                    placeholderText: Tr.tr("Message this session…")
                    onAccepted: root.sendCurrent()
                    onTextEdited: ChatService.input = text

                    Keys.onPressed: event => {
                        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                            root.sendCurrent();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.exitChat();
                            event.accepted = true;
                        }
                    }
                }

                IconButton {
                    icon: "send"
                    type: IconButton.Filled
                    enabled: !ChatService.asking && !!inputField.text.trim()
                    opacity: enabled ? 1 : 0.45
                    onClicked: root.sendCurrent()
                }
            }

            StyledText {
                visible: !!ChatService.error && !ChatService.response
                Layout.fillWidth: true
                text: ChatService.error
                color: Colours.palette.m3error
                font: Tokens.font.body.medium
                wrapMode: Text.Wrap
            }
        }
    }

    Timer {
        id: scrollTimer

        interval: 40
        repeat: false
        onTriggered: root.scrollToBottom()
    }

    Connections {
        target: ChatService

        function onActiveSessionIdChanged(): void {
            scrollTimer.restart();
        }

        function onAskingChanged(): void {
            scrollTimer.restart();
        }
    }
}
