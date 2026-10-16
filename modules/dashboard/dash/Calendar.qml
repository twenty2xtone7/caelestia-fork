pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

CustomMouseArea {
    id: root

    required property ScreenState screenState

    property date currentDate: screenState.dashboardDate
    readonly property int currMonth: currentDate.getMonth()
    readonly property int currYear: currentDate.getFullYear()
    readonly property int nonAnimCurrMonth: screenState.dashboardDate.getMonth()
    readonly property int nonAnimCurrYear: screenState.dashboardDate.getFullYear()

    readonly property int animDirection: screenState.dashboardDate > currentDate ? -1 : 1
    property real animTranslate
    property real animOpacity: 1

    property date selectedDate: new Date()

    onSelectedDateChanged: gridBox.updateSunny(false)

    function onWheel(event) {
        if (event.angleDelta.y > 0)
            screenState.dashboardDate = new Date(nonAnimCurrYear, nonAnimCurrMonth - 1, 1);
        else if (event.angleDelta.y < 0)
            screenState.dashboardDate = new Date(nonAnimCurrYear, nonAnimCurrMonth + 1, 1);
    }

    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: inner.implicitHeight + inner.anchors.margins * 2

    // No click-to-reset here: middle click now toggles marks on dates
    // (handled per-cell), so a card-level MMB reset would cause
    // accidental jumps.

    // When CalendarData.dataRevision changes, the delegate properties below
    // that reference it will automatically re-evaluate, so no explicit refresh call needed.

    Anim {
        id: trOutAnim

        running: false
        target: root
        property: "animTranslate"
        to: root.Tokens.padding.extraLarge * root.animDirection
        type: Anim.FastSpatial
    }

    Behavior on currentDate {
        SequentialAnimation {
            ParallelAnimation {
                ScriptAction {
                    script: Qt.callLater(() => trOutAnim.start())
                }
                Anim {
                    target: root
                    property: "animOpacity"
                    to: 0
                    type: Anim.FastEffects
                }
            }
            ScriptAction {
                script: {
                    trOutAnim.complete();
                    root.animTranslate = root.Tokens.padding.extraLarge * -root.animDirection;
                }
            }
            PropertyAction {}
            ParallelAnimation {
                Anim {
                    target: root
                    property: "animTranslate"
                    to: 0
                    type: Anim.DefaultSpatial
                }
                Anim {
                    target: root
                    property: "animOpacity"
                    to: 1
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    ColumnLayout {
        id: inner

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            id: monthNavigationRow

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            // Year back
            IconButton {
                isRound: true
                icon: "keyboard_double_arrow_left"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
                onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear - 1, root.nonAnimCurrMonth, 1)
            }

            // Month back
            IconButton {
                isRound: true
                icon: "chevron_left"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
                onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth - 1, 1)
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                implicitWidth: monthYearDisplay.implicitWidth + Tokens.padding.large * 2
                implicitHeight: monthYearDisplay.implicitHeight + Tokens.padding.extraSmall * 2

                StateLayer {
                    color: Colours.palette.m3primary
                    radius: pressed ? Tokens.rounding.small : height / 2
                    disabled: {
                        const now = new Date();
                        return root.nonAnimCurrMonth === now.getMonth() && root.nonAnimCurrYear === now.getFullYear();
                    }
                    onClicked: {
                        root.screenState.dashboardDate = new Date();
                        root.selectedDate = new Date();
                    }

                    Behavior on radius {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                StyledText {
                    id: monthYearDisplay

                    opacity: root.animOpacity
                    transform: Translate {
                        x: root.animTranslate
                    }

                    anchors.centerIn: parent
                    text: grid.title
                    color: Colours.palette.m3primary
                    font: Tokens.font.title.builders.small.capitalisation(Font.Capitalize).build()
                }
            }

            IconButton {
                isRound: true
                icon: "chevron_right"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
                onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth + 1, 1)
            }

            // Year forward
            IconButton {
                isRound: true
                icon: "keyboard_double_arrow_right"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
                onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear + 1, root.nonAnimCurrMonth, 1)
            }
        }

        DayOfWeekRow {
            id: daysRow

            Layout.fillWidth: true
            locale: grid.locale

            delegate: StyledText {
                required property var model

                horizontalAlignment: Text.AlignHCenter
                text: model.shortName
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: (model.day === 0 || model.day === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
            }
        }

        Item {
            id: gridBox

            Layout.fillWidth: true
            implicitHeight: grid.implicitHeight

            opacity: root.animOpacity
            transform: Translate {
                x: root.animTranslate
            }

            // When the selection changes, the sunny highlight travels from
            // the previous cell to the new one (Behaviors on x/y/size).
            // Grid re-layouts (month/year change, delegate rebuilds) snap
            // it instantly instead, so it never slides across a changing
            // grid. Hidden while the selected date is off-grid. It sits
            // BEHIND the grid so the date number, mark badge and
            // event/note dots always paint on top — no Colouriser copy
            // needed, which was the old center artifact.
            property bool selectionAnim: false

            // True when the selected date is today: the sunny shape then
            // uses the primary today styling, otherwise tonal styling.
            readonly property bool selectionIsToday: {
                const s = root.selectedDate;
                const t = new Date();
                return s.getFullYear() === t.getFullYear()
                    && s.getMonth() === t.getMonth()
                    && s.getDate() === t.getDate();
            }

            function sameDay(a, b) {
                return a.getFullYear() === b.getFullYear()
                    && a.getMonth() === b.getMonth()
                    && a.getDate() === b.getDate();
            }

            function selectedCell() {
                if (!grid.contentItem)
                    return null;
                const kids = grid.contentItem.children;
                for (let i = 0; i < kids.length; i++) {
                    const c = kids[i];
                    if (c && c.itemDate !== undefined && sameDay(c.itemDate, root.selectedDate))
                        return c;
                }
                return null;
            }

            function updateSunny(snap) {
                const cell = selectedCell();
                if (!cell) {
                    sunnyIndicator.visible = false;
                    return;
                }
                const size = Math.max(cell.implicitWidth, cell.implicitHeight) + Tokens.padding.extraSmall * 2;
                const nx = cell.x + (cell.width - size) / 2;
                const ny = cell.y - Tokens.padding.extraSmall - 1;
                selectionAnim = !snap;
                sunnyIndicator.x = nx;
                sunnyIndicator.y = ny;
                sunnyIndicator.implicitSize = size;
                sunnyIndicator.visible = true;
                selectionAnim = true;
            }

            Component.onCompleted: Qt.callLater(() => gridBox.updateSunny(true))

            // Shared travelling Material You highlight, painted BEHIND the
            // grid so numbers and dots stay visible. Primary when the
            // selection is today, tonal secondary-container otherwise.
            MaterialShape {
                id: sunnyIndicator

                visible: false
                shape: MaterialShape.Sunny

                clip: true
                color: gridBox.selectionIsToday ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                Behavior on x {
                    enabled: gridBox.selectionAnim
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
                Behavior on y {
                    enabled: gridBox.selectionAnim
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
                Behavior on implicitSize {
                    enabled: gridBox.selectionAnim
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
            }

            Connections {
                target: grid
                function onMonthChanged() {
                    Qt.callLater(() => gridBox.updateSunny(true));
                }
                function onYearChanged() {
                    Qt.callLater(() => gridBox.updateSunny(true));
                }
                // Grid resizes (dashboard/card layout changes) can
                // reposition cells without rebuilding delegates — re-snap
                // so the sunny shape stays locked to its date cell.
                function onWidthChanged() {
                    Qt.callLater(() => gridBox.updateSunny(true));
                }
                function onHeightChanged() {
                    Qt.callLater(() => gridBox.updateSunny(true));
                }
            }

            Connections {
                target: grid.contentItem
                function onChildrenChanged() {
                    Qt.callLater(() => gridBox.updateSunny(true));
                }
            }

            MonthGrid {
                id: grid

                month: root.currMonth
                year: root.currYear

                anchors.fill: parent

                spacing: 3
                locale: Qt.locale()

                delegate: Item {
                    id: dayItem

                    required property var model

                    readonly property date itemDate: model.date
                    readonly property bool isToday: {
                        const date = itemDate;
                        const today = new Date();
                        return date.getDate() === today.getDate() &&
                               date.getMonth() === today.getMonth() &&
                               date.getFullYear() === today.getFullYear();
                    }
                    // These force re-evaluation when dataRevision changes
                    readonly property bool isMarked: { CalendarData.dataRevision; CalendarData.isMarked(itemDate) }
                    readonly property bool hasData: { CalendarData.dataRevision; CalendarData.hasEventsOrNotes(itemDate) }
                    // Selected-date highlight so left-clicking any date —
                    // including empty ones — gives visible feedback.
                    readonly property bool isSelected: {
                        const s = root.selectedDate;
                        return s.getFullYear() === itemDate.getFullYear()
                            && s.getMonth() === itemDate.getMonth()
                            && s.getDate() === itemDate.getDate();
                    }

                    implicitWidth: implicitHeight
                    implicitHeight: dayContent.implicitHeight + Tokens.padding.small

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        // LMB selects, MMB toggles the mark X, RMB opens
                        // the list view (with add buttons). Creating stays
                        // explicit — no click ever creates anything.
                        onClicked: mouse => {
                            root.selectedDate = dayItem.itemDate;
                            if (mouse.button === Qt.MiddleButton) {
                                CalendarData.toggleMark(dayItem.itemDate);
                            } else if (mouse.button === Qt.RightButton) {
                                CalendarUi.requestList(dayItem.itemDate);
                            }
                        }
                    }

                    ColumnLayout {
                        id: dayContent
                        anchors.centerIn: parent
                        spacing: 1

                        Item {
                            id: dateCell
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: dayTextContainer.implicitWidth
                            implicitHeight: dayTextContainer.implicitHeight

                            // (No per-date today fill: the travelling sunny
                            // shape is the only highlight. Today is styled
                            // through it whenever it is the selection.)

                            StyledText {
                                id: dayTextContainer
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: grid.locale.toString(dayItem.model.day)
                                padding: 4

                                color: {
                                    if (dayItem.isSelected)
                                        return gridBox.selectionIsToday ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer;

                                    const dayOfWeek = dayItem.itemDate.getDay();
                                    if (dayOfWeek === 0 || dayOfWeek === 6)
                                        return Colours.palette.m3tertiary;

                                    return Colours.palette.m3onSurfaceVariant;
                                }

                                opacity: dayItem.model.today || dayItem.model.month === grid.month ? 1 : 0.4
                                font: Tokens.font.body.small
                            }

                            // Manual mark badge pinned to the date circle's
                            // top-right corner — shaded slightly darker than
                            // the base secondary tone so it stands out.
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: -3
                                anchors.rightMargin: -5
                                width: 14
                                height: 14
                                radius: 7
                                visible: dayItem.isMarked
                                color: Qt.darker(Colours.palette.m3secondary, 1.25)

                                // X drawn from two centered bars instead of a
                                // font glyph, so it is centered geometrically
                                // rather than relying on glyph bearings.
                                Item {
                                    anchors.centerIn: parent
                                    width: 8
                                    height: 8

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8
                                        height: 1.8
                                        radius: 0.9
                                        rotation: 45
                                        color: Colours.palette.m3onSecondary
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8
                                        height: 1.8
                                        radius: 0.9
                                        rotation: -45
                                        color: Colours.palette.m3onSecondary
                                    }
                                }
                            }
                        }

                        // Fixed-height indicator slot: reserves space even
                        // when empty so cells never jump when events/notes
                        // are added or removed.
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: dotsRow.implicitWidth
                            Layout.preferredHeight: 6

                            Row {
                                id: dotsRow
                                anchors.centerIn: parent
                                spacing: 2
                                visible: dayItem.hasData

                                Repeater {
                                    model: {
                                        CalendarData.dataRevision;
                                        const events = CalendarData.getEvents(dayItem.itemDate);
                                        return Math.min(events.length, 2);
                                    }

                                    Rectangle {
                                        required property int index

                                        width: 3
                                        height: 3
                                        radius: 1.5
                                        color: {
                                            CalendarData.dataRevision;
                                            const events = CalendarData.getEvents(dayItem.itemDate);
                                            if (events[index])
                                                return events[index].color || "#FF6200EE";
                                            return "#FF6200EE";
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: Colours.palette.m3outline
                                    visible: { CalendarData.dataRevision; CalendarData.getNote(dayItem.itemDate).length > 0 }
                                }
                            }
                        }
                    }
                }
        }
        }

    }
}
