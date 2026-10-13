pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls

Item {
    id: root

    anchors.fill: parent
    visible: false
    z: 1000

    signal confirmed()
    signal dismissed()
    signal dismiss()

    property string title: "Confirm"
    property string message: ""
    property string confirmLabel: "Confirm"
    property string cancelLabel: "Cancel"
    property string icon: ""

    function accept(): void {
        root.confirmed();
        root.visible = false;
    }

    function cancel(): void {
        root.dismissed();
        root.dismiss();
        root.visible = false;
    }

    onVisibleChanged: {
        if (visible)
            forceActiveFocus();
    }

    // Scrim
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

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: card

            anchors.centerIn: parent
            width: dialog.implicitWidth - Tokens.padding.large * 2
            spacing: Tokens.spacing.large

            RowLayout {
                spacing: Tokens.spacing.medium
                Layout.alignment: Qt.AlignHCenter

                Loader {
                    active: !!root.icon
                    Layout.alignment: Qt.AlignVCenter

                    sourceComponent: MaterialIcon {
                        text: root.icon
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.builders.large.build()
                    }
                }

                StyledText {
                    text: root.title
                    font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurface
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.message
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
                visible: !!root.message
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Tokens.spacing.small

                TextButton {
                    text: root.cancelLabel
                    type: TextButton.Text
                    onClicked: root.cancel()
                }

                TextButton {
                    text: root.confirmLabel
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
