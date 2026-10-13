import Quickshell
import qs.services

PersistentProperties {
    property list<string> expandedNotifs: []
    // Tall-dock flag for the expand-all button: grows the notification
    // page only. Groups stay exactly as they are (collapsed unless the
    // user opened them), so the button never unrolls rows by itself.
    property bool dockTall: false

    reloadableId: "sidebar"
}
