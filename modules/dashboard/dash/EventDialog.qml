pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    anchors.fill: parent
    anchors.margins: 0
    visible: false
    z: 1000
    clip: false

    property date selectedDate: new Date()
    property string eventId: ""
    property string mode: "create" // "create" or "edit"

    signal eventCreated()
    signal eventUpdated()
    signal eventDeleted()

    property string eventTitle: ""
    property string eventDescription: ""
    property string eventTime: ""
    property string eventColor: "#FF6200EE"

    function open(date, existingEventId) {
        existingEventId = existingEventId ?? "";
        root.selectedDate = date;
        root.eventId = existingEventId;

        if (existingEventId) {
            root.mode = "edit";
            const events = CalendarData.getEvents(date);
            const event = events.find(e => e.id === existingEventId);
            if (event) {
                root.eventTitle = event.title || "";
                root.eventDescription = event.description || "";
                root.eventTime = event.time || "";
                root.eventColor = event.color || "#FF6200EE";
            }
        } else {
            root.mode = "create";
            root.eventTitle = "";
            root.eventDescription = "";
            root.eventTime = "";
            root.eventColor = "#FF6200EE";
        }

        root.visible = true;
        // Sync fields imperatively (no `text:` binding, so typing never
        // re-triggers a binding write-back that jumps the cursor).
        titleField.text = root.eventTitle;
        timeField.text = root.eventTime;
        descriptionField.text = root.eventDescription;
        Qt.callLater(() => titleField.forceActiveFocus());
    }

    function accept() {
        if (!root.eventTitle.trim()) {
            root.cancel();
            return;
        }

        if (root.mode === "create") {
            CalendarData.createEvent(
                root.selectedDate,
                root.eventTitle.trim(),
                root.eventDescription.trim(),
                root.eventTime.trim(),
                "",
                root.eventColor
            );
            root.eventCreated();
        } else {
            CalendarData.updateEvent(
                root.selectedDate,
                root.eventId,
                {
                    title: root.eventTitle.trim(),
                    description: root.eventDescription.trim(),
                    time: root.eventTime.trim(),
                    color: root.eventColor
                }
            );
            root.eventUpdated();
        }

        titleField.focus = false;
        timeField.focus = false;
        descriptionField.focus = false;
        root.visible = false;
    }

    function cancel() {
        titleField.focus = false;
        timeField.focus = false;
        descriptionField.focus = false;
        root.visible = false;
    }

    function deleteEvent() {
        if (root.mode === "edit" && root.eventId) {
            CalendarData.deleteEvent(root.selectedDate, root.eventId);
            root.eventDeleted();
        }
        root.visible = false;
    }

    // NOTE: no forceActiveFocus() here — the root Item stealing focus is
    // what previously prevented typing (keys went to this Item instead of
    // the text fields). Focus is given to titleField in open().

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
        implicitWidth: Math.min(480, card.implicitWidth + Tokens.padding.large * 2)
        implicitHeight: card.implicitHeight + Tokens.padding.large * 2
        radius: LiquidGlass.enabled ? LiquidGlass.popupRadius : Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainerHigh

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: card

            anchors.centerIn: parent
            width: dialog.implicitWidth - Tokens.padding.large * 2
            spacing: Tokens.spacing.medium

            // Header
            RowLayout {
                spacing: Tokens.spacing.medium
                Layout.fillWidth: true

                MaterialIcon {
                    text: root.mode === "create" ? "event" : "edit_calendar"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.large.build()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.mode === "create" ? "New Event" : "Edit Event"
                    font: Tokens.font.title.builders.medium.build()
                    color: Colours.palette.m3onSurface
                }

                Loader {
                    active: root.mode === "edit"
                    visible: active

                    sourceComponent: IconButton {
                        icon: "delete"
                        type: IconButton.Text
                        onClicked: root.deleteEvent()
                    }
                }
            }

            // Date display
            StyledText {
                text: Qt.formatDate(root.selectedDate, "dddd, MMMM d, yyyy")
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurfaceVariant
            }

            // Title field
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: "Title"
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledTextField {
                    id: titleField
                    Layout.fillWidth: true
                    placeholderText: "Event title"
                    onTextEdited: root.eventTitle = text
                    Keys.onEscapePressed: root.cancel()
                }
            }

            // Time field
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: "Time (optional)"
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledTextField {
                    id: timeField
                    Layout.fillWidth: true
                    placeholderText: "e.g., 10:00 AM or 14:30"
                    onTextEdited: root.eventTime = text
                    Keys.onEscapePressed: root.cancel()
                }
            }

            // Description field
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: "Description (optional)"
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledTextField {
                    id: descriptionField
                    Layout.fillWidth: true
                    placeholderText: "Add details"
                    onTextEdited: root.eventDescription = text
                    Keys.onEscapePressed: root.cancel()
                }
            }

            // Color picker
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: "Color"
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                RowLayout {
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: ["#FF6200EE", "#FF0288D1", "#FF00796B", "#FF43A047", "#FFF57C00", "#FFD32F2F", "#FFC2185B", "#FF5E35B1"]

                        Rectangle {
                            required property var modelData
                            required property int index

                            width: 32
                            height: 32
                            radius: 16
                            color: modelData
                            border.width: root.eventColor === modelData ? 2 : 0
                            border.color: Colours.palette.m3onSurface

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.eventColor = parent.modelData
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                radius: 8
                                color: "white"
                                opacity: root.eventColor === parent.modelData ? 0.3 : 0
                            }
                        }
                    }
                }
            }

            // Buttons
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Tokens.spacing.small

                TextButton {
                    text: "Cancel"
                    type: TextButton.Text
                    onClicked: root.cancel()
                }

                TextButton {
                    text: root.mode === "create" ? "Create" : "Save"
                    type: TextButton.Filled
                    disabled: !root.eventTitle.trim()
                    onClicked: root.accept()
                }
            }
        }
    }

    Keys.onEscapePressed: root.cancel()
    Keys.onEnterPressed: {
        if (root.eventTitle.trim())
            root.accept();
    }
    Keys.onReturnPressed: {
        if (root.eventTitle.trim())
            root.accept();
    }
}
