pragma Singleton

import QtQuick
import Quickshell

// Transient UI coordination for calendar dialogs.
//
// Why this exists: calendar dialogs must be instantiated *outside* the
// dashboard ClippingRectangle (Content.qml > viewWrapper), otherwise the
// scrim only covers the small calendar card and the centered dialog card
// overflows its container and its MouseAreas misbehave. The Calendar grid
// lives deep inside a Flickable loader chain, so it cannot reach overlay
// items by id — it emits requests here, and the overlay host (instantiated
// once at Content root) listens and opens the right dialog.
Singleton {
    id: root

    signal openEvent(date date, string eventId)
    signal openNote(date date)
    signal openList(date date)

    function requestEvent(date, eventId) {
        root.openEvent(date, eventId ?? "");
    }

    function requestNote(date) {
        root.openNote(date);
    }

    function requestList(date) {
        root.openList(date);
    }
}
