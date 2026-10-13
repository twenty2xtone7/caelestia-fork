import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.launcher.services

// Side panel pinned to the highlighted launcher app (see Uninstall.panelEntry).
// Opened from the row trash button or the Right arrow key. Offers launch,
// favourite / hide toggles and - the reason it exists - uninstall, which goes
// through the same resolve + confirm flow as everywhere else.
Item {
    id: root

    property var entry: null
    property var list: null

    // Lazily resolved removable target for entry (see refreshPkg).
    property string pkgKind: ""
    property string pkgTarget: ""
    property string pkgDetail: ""
    property string pkgExtra: ""
    property bool pkgResolving: false

    readonly property string appName: root.entry?.name ?? root.entry?.id ?? ""
    readonly property bool isFav: root.entry ? Strings.testRegexList(GlobalConfig.launcher.favouriteApps, root.entry.id) : false
    readonly property bool favLocked: {
        if (!root.entry)
            return true;
        return GlobalConfig.launcher.favouriteApps.some(f => /^\^.*\$$/.test(f) && new RegExp(f).test(root.entry.id));
    }

    function pkgLine(): string {
        if (root.pkgResolving)
            return Tr.tr("Resolving package…");
        if (root.pkgKind === "")
            return Tr.tr("Package info unavailable");
        if (root.pkgKind === "none") {
            if (root.pkgDetail === "protected")
                return Tr.tr("System component — cannot remove");
            const m = Uninstall.manualPath(root.pkgDetail);
            if (m) {
                let s = Tr.tr("Not managed:\n%1").arg(m);
                const bin = Uninstall.extraBinInfo(root.pkgExtra ?? "");
                if (bin && bin.path)
                    s += "\n" + bin.path;
                return s;
            }
            return Tr.tr("No package found");
        }
        return Uninstall.describeTarget(root.pkgKind, root.pkgTarget, root.pkgDetail, root.pkgExtra);
    }

    function refreshPkg(): void {
        root.pkgKind = "";
        root.pkgTarget = "";
        root.pkgDetail = "";
        root.pkgExtra = "";
        const id = root.entry?.id;
        if (!id || Uninstall.resolver.running)
            return; // busy with another op; Delete falls back to full resolve
        root.pkgResolving = true;
        if (!Uninstall.resolve(root.entry, (kind, target, detail, extra) => {
            root.pkgResolving = false;
            if ((root.entry?.id ?? "") !== id)
                return; // stale: selection moved on while resolving
            root.pkgKind = kind;
            root.pkgTarget = target;
            root.pkgDetail = detail;
            root.pkgExtra = extra ?? "";
        }))
            root.pkgResolving = false;
    }

    onEntryChanged: root.refreshPkg()
    Component.onCompleted: root.refreshPkg()

    function closeAll(): void {
        const ss = root.list?.screenState ?? root.list;
        Uninstall.closePanel();
        if (ss && ss.launcher !== undefined)
            ss.launcher = false;
    }

    function deleteApp(): void {
        if (root.pkgKind !== "")
            Uninstall.requestResolved(root.pkgKind, root.pkgTarget, root.pkgDetail, root.pkgExtra, root.appName, root.list);
        else if (root.entry)
            Uninstall.request(root.entry, root.list);
    }

    function toggleFav(): void {
        const id = root.entry?.id;
        if (!id)
            return;
        const apps = GlobalConfig.launcher.favouriteApps;
        GlobalConfig.launcher.favouriteApps = root.isFav ? apps.filter(a => a !== id) : [...apps, id];
    }

    function hideApp(): void {
        const id = root.entry?.id;
        if (!id)
            return;
        const apps = GlobalConfig.launcher.hiddenApps;
        if (!apps.includes(id))
            GlobalConfig.launcher.hiddenApps = [...apps, id];
        Uninstall.closePanel();
    }

    Column {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Tokens.spacing.medium

            IconImage {
                asynchronous: true
                source: Quickshell.iconPath(root.entry?.icon, "image-missing")
                implicitSize: 52

                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 52 - Tokens.spacing.medium
                spacing: 2

                StyledText {
                    width: parent.width
                    text: root.appName
                    font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: (root.entry?.comment || root.entry?.genericName) ?? ""
                    visible: text !== ""
                    font: Tokens.font.body.small
                    color: Colours.palette.m3outline
                    elide: Text.ElideRight
                }
            }
        }

        StyledText {
            anchors.left: parent.left
            anchors.right: parent.right
            text: root.pkgLine()
            font: Tokens.font.label.small
            color: Colours.palette.m3outlineVariant
            wrapMode: Text.WordWrap
        }

        IconTextButton {
            anchors.left: parent.left
            anchors.right: parent.right
            icon: "open_in_new"
            text: Tr.tr("Launch")
            type: IconTextButton.Filled
            onClicked: {
                if (root.entry)
                    Apps.launch(root.entry);
                root.closeAll();
            }
        }

        IconTextButton {
            anchors.left: parent.left
            anchors.right: parent.right
            icon: "delete"
            text: Tr.tr("Uninstall")
            inactiveColour: Colours.palette.m3error
            inactiveOnColour: Colours.palette.m3onError
            activeColour: Colours.palette.m3error
            activeOnColour: Colours.palette.m3onError
            disabled: root.pkgKind === "none"
            onClicked: root.deleteApp()
        }

        IconTextButton {
            anchors.left: parent.left
            anchors.right: parent.right
            icon: "favorite"
            text: root.isFav ? Tr.tr("Unfavourite") : Tr.tr("Favourite")
            type: IconTextButton.Tonal
            disabled: root.favLocked || !root.entry
            onClicked: root.toggleFav()
        }

        IconTextButton {
            anchors.left: parent.left
            anchors.right: parent.right
            icon: "visibility_off"
            text: Tr.tr("Hide from launcher")
            type: IconTextButton.Tonal
            disabled: !root.entry
            onClicked: root.hideApp()
        }
    }

    StyledText {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large
        horizontalAlignment: Text.AlignHCenter
        text: Tr.tr("← / Esc to go back")
        font: Tokens.font.label.small
        color: Colours.palette.m3outlineVariant
    }
}
