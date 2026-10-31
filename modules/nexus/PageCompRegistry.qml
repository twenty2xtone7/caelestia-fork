pragma Singleton

import QtQuick
import QtQuick.Layouts
import Caelestia.I18n
// Static imports below are intentional: besides compile-time checking,
// they ensure the QML engine resolves the qs page modules so the
// dynamic Qt.createComponent(Qt.resolvedUrl(...)) loads in Pages.qml succeed.
import qs.modules.nexus.common
import qs.modules.nexus.pages
import qs.modules.nexus.pages.wallandstyle
import qs.modules.nexus.pages.liquidglass
import qs.modules.nexus.pages.network
import qs.modules.nexus.pages.bluetooth
import qs.modules.nexus.pages.audio
import qs.modules.nexus.pages.panels
import qs.modules.nexus.pages.panels.taskbar
import qs.modules.nexus.pages.apps
import qs.modules.nexus.pages.services
import qs.modules.nexus.pages.recordings
import qs.modules.nexus.pages.dynlyrics

QtObject {
    // Dynamic string URLs. Order of entries must match PageRegistry.pages;
    // order of subPages must match nState.openSubPage(idx) callers.
    readonly property list<var> pages: [
        {
            url: "pages/WallpaperAndStyle.qml",
            subPages: [
                "pages/WallpaperAndStyle.qml",
                "pages/wallandstyle/WallpaperSelect.qml",
                "pages/wallandstyle/WallpaperCategory.qml",
                "pages/wallandstyle/ColourSelect.qml",
                "pages/wallandstyle/SnowPage.qml"
            ]
        },
        {
            url: "pages/liquidglass/LiquidGlassPage.qml",
            subPages: ["pages/liquidglass/LiquidGlassPage.qml"]
        },
        {
            url: "pages/NetworkPage.qml",
            subPages: [
                "pages/NetworkPage.qml",
                "pages/network/EthernetDetailPage.qml",
                "pages/network/AddNetworkPage.qml",
                "pages/network/NetworkDetailPage.qml",
                "pages/network/AddVpnPage.qml",
                "pages/network/AllNetworksPage.qml",
                "pages/network/SavedNetworksPage.qml"
            ]
        },
        {
            url: "pages/BluetoothPage.qml",
            subPages: [
                "pages/BluetoothPage.qml",
                "pages/bluetooth/BtDeviceInfo.qml",
                "pages/bluetooth/BluetoothPairing.qml"
            ]
        },
        {
            url: "pages/AudioPage.qml",
            subPages: [
                "pages/AudioPage.qml",
                "pages/audio/AppVolumes.qml"
            ]
        },
        { placeholder: true },
        { placeholder: true },
        {
            url: "pages/PanelsPage.qml",
            subPages: [
                "pages/PanelsPage.qml",
                "pages/panels/DashboardPanel.qml",
                "pages/panels/TaskbarPanel.qml",
                "pages/panels/LauncherPanel.qml",
                "pages/panels/SidebarPanel.qml",
                "pages/panels/UtilitiesPanel.qml",
                "pages/panels/taskbar/BarWorkspaces.qml",
                "pages/panels/taskbar/BarActiveWindow.qml",
                "pages/panels/taskbar/BarTray.qml",
                "pages/panels/taskbar/BarStatusIcons.qml",
                "pages/panels/taskbar/BarClock.qml"
            ]
        },
        {
            url: "pages/AppsPage.qml",
            subPages: [
                "pages/AppsPage.qml",
                "pages/apps/AllApps.qml",
                "pages/apps/AppInfo.qml"
            ]
        },
        {
            url: "pages/ServicesPage.qml",
            subPages: [
                "pages/ServicesPage.qml",
                "pages/services/NotificationsPage.qml",
                "pages/RadialMenuPage.qml"
            ]
        },
        {
            url: "pages/recordings/RecordingsPage.qml",
            subPages: ["pages/recordings/RecordingsPage.qml"]
        },
        {
            url: "pages/LanguageAndRegion.qml",
            subPages: ["pages/LanguageAndRegion.qml"]
        },
        {
            url: "pages/dynlyrics/DynLyricsPage.qml",
            subPages: ["pages/dynlyrics/DynLyricsPage.qml"]
        },
        {
            url: "pages/AboutPage.qml",
            subPages: ["pages/AboutPage.qml"]
        }
    ]

    readonly property Component placeholderComponent: Component {
        Item {
            property var nState
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Tr.tr("Page under construction")
                    font.pixelSize: 16
                }
            }
        }
    }
}
