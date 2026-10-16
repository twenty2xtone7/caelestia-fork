pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.utils

Singleton {
    id: root

    // Data structure:
    // {
    //   "marks": { "YYYY-MM-DD": true, ... },
    //   "events": {
    //     "YYYY-MM-DD": [
    //       { id, title, description, time, recurring, color },
    //       ...
    //     ]
    //   },
    //   "notes": { "YYYY-MM-DD": "note text", ... }
    // }

    readonly property string storePath: {
        const path = `${Paths.state}/calendar-data.json`;
        return path;
    }

    property var data: ({
        marks: {},
        events: {},
        notes: {}
    })

    property int dataRevision: 0

    property bool loaded: false

    signal changed()

    function dateKey(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    function parseDateKey(key) {
        const [year, month, day] = key.split('-').map(Number);
        return new Date(year, month - 1, day);
    }

    // ── Mark Operations ──

    function isMarked(date) {
        return dateKey(date) in root.data.marks;
    }

    function toggleMark(date) {
        const key = dateKey(date);
        if (key in root.data.marks) {
            delete root.data.marks[key];
        } else {
            root.data.marks[key] = true;
        }
        data = Object.assign({}, root.data);
        dataRevision++;
        root.save();
        root.changed();
    }

    // ── Event Operations ──

    // Check if a recurring event on its start date matches the given date.
    // recurrence rules: "daily", "weekly", "monthly", "yearly", "" (none)
    function _matchesRecurrence(evt, evtDate, targetDate) {
        if (!evt.recurring)
            return false;

        const startYear = evtDate.getFullYear();
        const startMonth = evtDate.getMonth();
        const startDay = evtDate.getDate();
        const startDayOfWeek = evtDate.getDay();
        const targetYear = targetDate.getFullYear();
        const targetMonth = targetDate.getMonth();
        const targetDay = targetDate.getDate();
        const targetDayOfWeek = targetDate.getDay();

        // Target must be on or after start date
        if (targetDate.getTime() < evtDate.getTime())
            return false;

        switch (evt.recurring) {
            case "daily":
                return true;
            case "weekly":
                return targetDayOfWeek === startDayOfWeek;
            case "monthly":
                return targetDay === startDay;
            case "yearly":
                return targetMonth === startMonth && targetDay === startDay;
            default:
                return false;
        }
    }

    // Return events that apply to the given date, including recurring events
    // that were created on a prior date but match this one.
    function getEvents(date) {
        const key = dateKey(date);
        const direct = root.data.events[key] ?? [];

        // Gather recurring events from all earlier dates
        const recurring = [];
        const eventsByDate = root.data.events;
        for (const dateKeyStr in eventsByDate) {
            const evtDate = parseDateKey(dateKeyStr);
            // Skip the same key (already in direct) and future dates
            if (dateKeyStr === key)
                continue;
            if (evtDate.getTime() > date.getTime())
                continue;
            for (let i = 0; i < eventsByDate[dateKeyStr].length; i++) {
                const evt = eventsByDate[dateKeyStr][i];
                if (evt.recurring && _matchesRecurrence(evt, evtDate, date)) {
                    recurring.push(evt);
                }
            }
        }

        if (recurring.length === 0)
            return direct;

        // Merge: direct events first, then recurring
        return direct.concat(recurring);
    }

    function createEvent(date, title, description, time, recurring, color) {
        description = description ?? "";
        time = time ?? "";
        recurring = recurring ?? "";
        color = color ?? "#FF6200EE";
        const key = dateKey(date);
        if (!(key in root.data.events)) {
            root.data.events[key] = [];
        }

        const id = `evt_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        const event = {
            id,
            title,
            description,
            time,
            recurring,
            color,
            created: new Date().toISOString()
        };

        root.data.events[key].push(event);
        data = Object.assign({}, root.data);
        dataRevision++;
        root.save();
        root.changed();
        return id;
    }

    function updateEvent(date, eventId, updates) {
        const key = dateKey(date);
        if (key in root.data.events) {
            const idx = root.data.events[key].findIndex(e => e.id === eventId);
            if (idx >= 0) {
                root.data.events[key][idx] = Object.assign({}, root.data.events[key][idx], updates);
                data = Object.assign({}, root.data);
                dataRevision++;
                root.save();
                root.changed();
            }
        }
    }

    function deleteEvent(date, eventId) {
        const key = dateKey(date);
        if (key in root.data.events) {
            root.data.events[key] = root.data.events[key].filter(e => e.id !== eventId);
            if (root.data.events[key].length === 0) {
                delete root.data.events[key];
            }
            data = Object.assign({}, root.data);
            dataRevision++;
            root.save();
            root.changed();
        }
    }

    // ── Note Operations ──

    function getNote(date) {
        const key = dateKey(date);
        return root.data.notes[key] ?? "";
    }

    function setNote(date, note) {
        const key = dateKey(date);
        if (note && note.trim()) {
            root.data.notes[key] = note.trim();
        } else if (key in root.data.notes) {
            delete root.data.notes[key];
        }
        data = Object.assign({}, root.data);
        dataRevision++;
        root.save();
        root.changed();
    }

    function hasEventsOrNotes(date) {
        const events = getEvents(date);
        const note = getNote(date);
        return events.length > 0 || note.length > 0;
    }

    // ── Persistence ──

    function save() {
        try {
            const json = JSON.stringify(root.data, null, 2);
            storage.setText(json);
        } catch (e) {
            console.error("CalendarData: failed to serialize data:", e);
        }
    }

    function load() {
        // storage.onLoaded signal will handle this
    }

    function clear() {
        root.data = {
            marks: {},
            events: {},
            notes: {}
        };
        dataRevision++;
        root.save();
        root.changed();
    }

    FileView {
        id: storage

        printErrors: false
        path: root.storePath
        onLoaded: {
            try {
                const loaded = JSON.parse(text());
                root.data = Object.assign({
                    marks: {},
                    events: {},
                    notes: {}
                }, loaded);
                dataRevision++;
            } catch (e) {
                console.warn("CalendarData: failed to parse calendar data, using defaults:", e);
            }
            root.loaded = true;
            root.changed();
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                Qt.callLater(() => {
                    storage.setText(JSON.stringify(root.data, null, 2));
                });
            } else {
                console.warn("CalendarData: failed to load calendar data:", err);
            }
            dataRevision++;
            root.loaded = true;
            root.changed();
        }
    }
}
