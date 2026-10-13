import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

// Modal confirmation for destructive Universal Action Launcher commands
// (reboot, shutdown, kill, uninstall, ...) plus the launcher app
// right-click uninstall flow (Uninstall.pendingConfirm). Mounted over the
// launcher content and only active while either is set. Nothing executes
// until the user explicitly accepts. Emits `closed` so the host can
// restore focus.
Item {
    id: root

    anchors.fill: parent
    visible: CommandRegistry.pendingConfirm !== null || Uninstall.pendingConfirm !== null
    z: 1000

    signal closed

    readonly property var activeConfirm: CommandRegistry.pendingConfirm ?? Uninstall.pendingConfirm

    function accept(): void {
        if (CommandRegistry.pendingConfirm)
            CommandRegistry.acceptPending();
        else
            Uninstall.accept();
        root.closed();
    }

    function cancel(): void {
        if (CommandRegistry.pendingConfirm)
            CommandRegistry.cancelPending();
        else
            Uninstall.cancel();
        root.closed();
    }

    onVisibleChanged: {
        if (visible)
            forceActiveFocus();
        else
            root.closed();
    }

    // Scrim; clicking outside cancels.
    StyledRect {
        anchors.fill: parent
        color: Colours.palette.m3scrim
        opacity: 0.5
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.cancel()
    }

    StyledRect {
        id: dialog

        anchors.centerIn: parent
        implicitWidth: Math.min(420, card.implicitWidth + Tokens.padding.large * 2)
        implicitHeight: card.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainerHigh

        // Swallow clicks so they don't reach the scrim.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: card

            anchors.centerIn: parent
            width: dialog.implicitWidth - Tokens.padding.large * 2
            spacing: Tokens.spacing.large

            StyledText {
                Layout.fillWidth: true
                text: root.activeConfirm?.title ?? ""
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Tokens.spacing.small

                TextButton {
                    text: Tr.tr("Cancel")
                    type: TextButton.Text
                    onClicked: root.cancel()
                }

                TextButton {
                    text: root.activeConfirm?.accept ?? Tr.tr("Confirm")
                    type: TextButton.Filled
                    onClicked: root.accept()
                }
            }
        }
    }

    Keys.onEscapePressed: root.cancel()
    Keys.onEnterPressed: root.accept()
    Keys.onReturnPressed: root.accept()
}
