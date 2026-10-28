pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.launcher.services

Item {
    id: root

    required property var content
    required property ScreenState screenState
    required property var panels
    required property real maxHeight
    required property SearchBar search
    required property int padding
    required property int rounding

    readonly property bool showWallpapers: search.text.startsWith(`${GlobalConfig.launcher.actionPrefix}wallpaper `)
    readonly property bool showTranslate: Actions.activeMiniApp === "translate"
    readonly property bool showMusic: Actions.activeMiniApp === "music"
    readonly property bool showFan: Actions.activeMiniApp === "fan"
    readonly property bool showNight: Actions.activeMiniApp === "night"
    readonly property bool showClipboard: Actions.activeMiniApp === "clipboard" || ClipboardService.open
    readonly property var currentList: showClipboard ? clipboardView.item?.list : showTranslate || showMusic || showFan || showNight ? null : showWallpapers ? wallpaperList.item : appList.item // Can be either ListView or PathView, so can't type properly

    function collapseClipboardPreview(): bool {
        if (clipboardView.item?.previewExpanded) {
            clipboardView.item.previewExpanded = false;
            return true;
        }
        return false;
    }

    function toggleClipboardPreview(): bool {
        const item = clipboardView.item;
        if (!item?.currentEntry?.isImage)
            return false;
        item.previewExpanded = !item.previewExpanded;
        return true;
    }
    property string animState: showClipboard ? "clipboard" : showTranslate ? "translate" : showMusic ? "music" : showFan ? "fan" : showNight ? "night" : showWallpapers ? "wallpapers" : "apps"

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom

    clip: true
    state: animState

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: {
                    const contentHeight = appList.implicitHeight > 0 ? appList.implicitHeight : empty.implicitHeight;
                    const floor = Uninstall.panelOpen ? Tokens.sizes.launcher.itemHeight * 7 : 0;
                    return Math.min(root.maxHeight, Math.max(floor, contentHeight));
                }
                appList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "translate"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth * 1.2
                root.implicitHeight: Math.min(root.maxHeight, translateView.implicitHeight > 0 ? translateView.implicitHeight : empty.implicitHeight)
                translateView.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "music"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth * 1.3
                root.implicitHeight: Math.min(root.maxHeight, musicView.implicitHeight > 0 ? musicView.implicitHeight : empty.implicitHeight)
                musicView.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "fan"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth * 1.2
                root.implicitHeight: Math.min(root.maxHeight, fanView.implicitHeight > 0 ? fanView.implicitHeight : empty.implicitHeight)
                fanView.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "night"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth * 1.2
                root.implicitHeight: Math.min(root.maxHeight, nightView.implicitHeight > 0 ? nightView.implicitHeight : empty.implicitHeight)
                nightView.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "clipboard"
            PropertyChanges {                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth * 1.35
                root.implicitHeight: Math.min(root.maxHeight, clipboardView.implicitHeight > 0 ? clipboardView.implicitHeight : empty.implicitHeight)
                clipboardView.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "wallpapers"

            PropertyChanges {
                root.implicitWidth: Math.max(root.Tokens.sizes.launcher.itemWidth * 1.2, wallpaperList.implicitWidth)
                root.implicitHeight: root.Tokens.sizes.launcher.wallpaperHeight + (wallpaperList.item?.filterBarHeight ?? 0)
                wallpaperList.active: true
            }
        }
    ]

    Behavior on animState {
        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                from: 1
                to: 0
                type: Anim.DefaultEffects
            }
            PropertyAction {}
            Anim {
                target: root
                property: "opacity"
                from: 0
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: appList

        active: false

        anchors.fill: parent

        sourceComponent: AppList {
            objectName: "launcherAppList"

            search: root.search
            screenState: root.screenState
        }
    }

    Loader {
        id: wallpaperList

        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: WallpaperList {
            objectName: "launcherWallpaperList"

            search: root.search
            screenState: root.screenState
            panels: root.panels
            content: root.content
        }
    }

    Loader {
        id: translateView

        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        sourceComponent: TranslateView {
            objectName: "launcherTranslateView"

            screenState: root.screenState
            search: root.search
        }
    }

    Loader {
        id: musicView

        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        sourceComponent: MusicView {
            objectName: "launcherMusicView"

            screenState: root.screenState
            search: root.search
        }
    }

    Loader {
        id: fanView

        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        sourceComponent: FanView {
            objectName: "launcherFanView"

            screenState: root.screenState
            search: root.search
        }
    }

    Loader {
        id: nightView

        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        sourceComponent: NightView {
            objectName: "launcherNightView"

            screenState: root.screenState
            search: root.search
        }
    }

    Loader {
        id: clipboardView

        // Build rows off the open path: the window appears instantly and
        // the list fades in right after, instead of blocking the toggle.
        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        sourceComponent: ClipboardView {
            objectName: "launcherClipboardView"

            screenState: root.screenState
            search: root.search
        }
    }

    Row {
        id: empty

        opacity: root.state === "clipboard" ? 0 : root.currentList?.count === 0 ? 1 : 0
        scale: root.state === "clipboard" ? 0.5 : root.currentList?.count === 0 ? 1 : 0.5

        spacing: Tokens.spacing.medium
        padding: Tokens.padding.large

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        MaterialIcon {
            text: {
                if (root.state === "wallpapers")
                    return "wallpaper_slideshow";
                return "manage_search";
            }
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: {
                    if (root.state === "wallpapers")
                        return Tr.tr("No wallpapers found");
                    return Tr.tr("No results");
                }
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                text: {
                    if (root.state === "wallpapers" && Wallpapers.list.length === 0)
                        return Tr.tr("Try putting some wallpapers in %1").arg(Paths.shortenHome(Paths.wallsdir));
                    return Tr.tr("Try searching for something else");
                }
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }
    }

    Behavior on implicitWidth {
        enabled: root.screenState.launcher

        Anim {}
    }

    Behavior on implicitHeight {
        enabled: root.screenState.launcher

        Anim {}
    }
}
