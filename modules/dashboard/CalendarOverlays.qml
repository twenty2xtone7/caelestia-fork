pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import "dash"

// Calendar dialog overlays, instantiated ONCE at Content root (outside the
// viewWrapper ClippingRectangle). Previously these lived inside Calendar.qml,
// so `anchors.fill: parent` only covered the small calendar card: the scrim
// did not block the surrounding cards and the centered card overflowed its
// container. Calendar.qml requests opens via the CalendarUi singleton.
Item {
    id: root

    anchors.fill: parent

    Connections {
        target: CalendarUi
        function onOpenEvent(date, eventId) {
            eventsList.close();
            eventDialog.open(date, eventId);
        }
        function onOpenNote(date) {
            noteDialog.open(date, CalendarData.getNote(date));
        }
        function onOpenList(date) {
            eventDialog.cancel();
            eventsList.open(date);
        }
    }

    // Event dialog (create / edit)
    EventDialog {
        id: eventDialog

        anchors.fill: parent
        z: 1000
    }

    // Note dialog
    Item {
        id: noteDialog

        anchors.fill: parent
        visible: false
        z: 999

        property date noteDate: new Date()
        property string existingNote: ""

        function open(date, note) {
            noteDialog.noteDate = date;
            noteDialog.existingNote = note || "";
            noteTextArea.text = noteDialog.existingNote;
            noteDialog.visible = true;
            Qt.callLater(() => noteTextArea.forceActiveFocus());
        }

        function accept() {
            CalendarData.setNote(noteDialog.noteDate, noteTextArea.text);
            noteTextArea.focus = false;
            noteDialog.visible = false;
        }

        function cancel() {
            noteTextArea.focus = false;
            noteDialog.visible = false;
        }

        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => noteTextArea.forceActiveFocus());
        }

        StyledRect {
            anchors.fill: parent
            color: Colours.palette.m3scrim
            opacity: 0.5
        }

        MouseArea {
            anchors.fill: parent
            onClicked: noteDialog.cancel()
        }

        StyledRect {
            id: noteCardBox

            anchors.centerIn: parent
            width: Math.min(420, parent.width - Tokens.padding.large * 2)
            height: Math.min(noteCard.implicitHeight + Tokens.padding.large * 2, parent.height - Tokens.padding.large * 2)
            radius: LiquidGlass.enabled ? LiquidGlass.popupRadius : Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainerHigh

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: noteCard

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    spacing: Tokens.spacing.medium
                    Layout.fillWidth: true

                    MaterialIcon {
                        text: "edit_note"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.builders.large.build()
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Note"
                        font: Tokens.font.title.builders.medium.build()
                        color: Colours.palette.m3onSurface
                    }
                }

                StyledText {
                    text: Qt.formatDate(noteDialog.noteDate, "dddd, MMMM d, yyyy")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    clip: true

                    TextArea {
                        id: noteTextArea

                        placeholderText: "Enter note..."
                        wrapMode: Text.Wrap
                        selectByMouse: true
                        color: Colours.palette.m3onSurface
                        placeholderTextColor: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.medium
                        background: Rectangle {
                            color: "transparent"
                        }

                        Keys.onEscapePressed: noteDialog.cancel()
                        Keys.onPressed: event => {
                            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                noteDialog.accept();
                                event.accepted = true;
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Tokens.spacing.small

                    TextButton {
                        text: "Cancel"
                        type: TextButton.Text
                        onClicked: noteDialog.cancel()
                    }

                    TextButton {
                        text: "Save"
                        type: TextButton.Filled
                        onClicked: noteDialog.accept()
                    }
                }
            }
        }

        Keys.onEscapePressed: noteDialog.cancel()
    }

    // Events list dialog
    Item {
        id: eventsList

        anchors.fill: parent
        visible: false
        z: 998

        property date listDate: new Date()

        function open(date) {
            eventsList.listDate = date;
            eventsList.visible = true;
            Qt.callLater(() => eventsList.forceActiveFocus());
        }

        function close() {
            eventsList.visible = false;
        }

        StyledRect {
            anchors.fill: parent
            color: Colours.palette.m3scrim
            opacity: 0.5
        }

        MouseArea {
            anchors.fill: parent
            onClicked: eventsList.close()
        }

        StyledRect {
            id: eventsCardBox

            anchors.centerIn: parent
            width: Math.min(480, parent.width - Tokens.padding.large * 2)
            height: Math.min(eventsCard.implicitHeight + Tokens.padding.large * 2, parent.height - Tokens.padding.large * 2)
            radius: LiquidGlass.enabled ? LiquidGlass.popupRadius : Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainerHigh

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: eventsCard

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    spacing: Tokens.spacing.medium
                    Layout.fillWidth: true

                    MaterialIcon {
                        text: "event"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.builders.large.build()
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Events"
                        font: Tokens.font.title.builders.medium.build()
                        color: Colours.palette.m3onSurface
                    }

                    IconButton {
                        icon: "close"
                        type: IconButton.Text
                        onClicked: eventsList.close()
                    }
                }

                StyledText {
                    text: Qt.formatDate(eventsList.listDate, "dddd, MMMM d, yyyy")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                }

                // Note attached to this date, if any. Kept live via
                // dataRevision so saving from the note editor refreshes
                // it while the list is open.
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: noteItemLayout.implicitHeight + Tokens.padding.medium * 2
                    radius: Tokens.rounding.medium
                    color: Colours.tPalette.m3surfaceContainer
                    visible: { CalendarData.dataRevision; return CalendarData.getNote(eventsList.listDate).length > 0; }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const d = eventsList.listDate;
                            eventsList.close();
                            CalendarUi.requestNote(d);
                        }
                    }

                    RowLayout {
                        id: noteItemLayout

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: "edit_note"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.builders.medium.build()
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: { CalendarData.dataRevision; return CalendarData.getNote(eventsList.listDate); }
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            maximumLineCount: 3
                        }

                        IconButton {
                            icon: "delete"
                            type: IconButton.Text
                            onClicked: CalendarData.setNote(eventsList.listDate, "")
                        }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: eventListView.count > 0 ? Math.min(320, Math.max(eventListView.contentHeight, 60)) : 0
                    Layout.maximumHeight: 320
                    clip: true
                    visible: eventListView.count > 0

                    ListView {
                        id: eventListView

                        // dataRevision reference forces refresh when events change
                        model: { CalendarData.dataRevision; return CalendarData.getEvents(eventsList.listDate); }
                        spacing: Tokens.spacing.small
                        clip: true

                        delegate: StyledRect {
                            required property var modelData
                            required property int index

                            width: ListView.view.width
                            implicitHeight: eventItemLayout.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.medium
                            color: Colours.tPalette.m3surfaceContainer

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const id = modelData.id;
                                    const d = eventsList.listDate;
                                    eventsList.close();
                                    eventDialog.open(d, id);
                                }
                            }

                            RowLayout {
                                id: eventItemLayout

                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                spacing: Tokens.spacing.medium

                                Rectangle {
                                    width: 4
                                    Layout.fillHeight: true
                                    radius: 2
                                    color: modelData.color || "#FF6200EE"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.extraSmall

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.title
                                        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                                        color: Colours.palette.m3onSurface
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.time || "All day"
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurfaceVariant
                                        visible: !!modelData.time
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.description
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurfaceVariant
                                        visible: !!modelData.description
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                IconButton {
                                    Layout.alignment: Qt.AlignTop
                                    icon: "delete"
                                    type: IconButton.Text
                                    onClicked: CalendarData.deleteEvent(eventsList.listDate, modelData.id)
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Tokens.spacing.small

                    TextButton {
                        text: "Add event"
                        type: TextButton.Tonal
                        onClicked: {
                            const d = eventsList.listDate;
                            eventsList.close();
                            eventDialog.open(d);
                        }
                    }

                    TextButton {
                        text: "Note"
                        type: TextButton.Tonal
                        onClicked: {
                            const d = eventsList.listDate;
                            eventsList.close();
                            CalendarUi.requestNote(d);
                        }
                    }

                    TextButton {
                        text: "Close"
                        type: TextButton.Text
                        onClicked: eventsList.close()
                    }
                }
            }
        }

        Keys.onEscapePressed: eventsList.close()
    }
}
