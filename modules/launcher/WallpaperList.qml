pragma ComponentBehavior: Bound

import "items"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property SearchBar search
    required property var screenState
    required property var panels
    required property var content

    // 0 = All, 1 = Animated (live/video), 2 = Static (image)
    property int category: 0

    // Remember the last chosen category across picker openings (and shell
    // restarts). The view is rebuilt each time the launcher enters the
    // wallpapers state, so this must persist outside the item.
    FileView {
        id: categoryStorage

        printErrors: false
        path: `${Paths.state}/launcher-wallpaper-category.txt`
        onLoaded: {
            const saved = parseInt(text().trim(), 10);
            if (saved >= 0 && saved <= 2)
                root.category = saved;
        }
        onLoadFailed: {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(String(root.category)));
        }
    }

    onCategoryChanged: categoryStorage.setText(String(root.category))

    // Forwarded PathView interface: Content.qml drives the active list
    // through currentItem / currentIndex / count / index stepping.
    readonly property alias currentItem: pathView.currentItem
    readonly property alias currentIndex: pathView.currentIndex
    readonly property alias count: pathView.count

    function incrementCurrentIndex() {
        pathView.incrementCurrentIndex();
    }

    function decrementCurrentIndex() {
        pathView.decrementCurrentIndex();
    }

    readonly property int animatedCount: [...Wallpapers.list].filter(w => Wallpapers.isLive(w.path)).length
    readonly property int staticCount: Wallpapers.list.length - animatedCount

    // Height consumed by the category bar (chips + top margin + gap to
    // the carousel). ContentList adds this on top of wallpaperHeight so
    // the carousel keeps its full size instead of being squeezed.
    readonly property real filterBarHeight: filterRow.implicitHeight + filterRow.Layout.topMargin + Tokens.spacing.small

    readonly property int itemWidth: Tokens.sizes.launcher.wallpaperWidth * 0.8 + Tokens.padding.medium * 2

    readonly property int numItems: {
        const screen = (QsWindow.window as QsWindow)?.screen;
        if (!screen)
            return 0;

        // Screen width - 4x outer rounding - 2x max side thickness (cause centered)
        const barMargins = Math.max(Config.border.thickness, panels.bar.implicitWidth);
        let outerMargins = 0;
        if (panels.popouts.hasCurrent && panels.popouts.currentCenter + panels.popouts.nonAnimHeight / 2 > screen.height - content.implicitHeight - Config.border.thickness * 2)
            outerMargins = panels.popouts.nonAnimWidth;
        if ((screenState.utilities || screenState.sidebar) && panels.utilities.implicitWidth > outerMargins)
            outerMargins = panels.utilities.implicitWidth;
        const maxWidth = screen.width - Config.border.rounding * 4 - (barMargins + outerMargins) * 2;

        if (maxWidth <= 0)
            return 0;

        const maxItemsOnScreen = Math.floor(maxWidth / itemWidth);
        const visible = Math.min(maxItemsOnScreen, Config.launcher.maxWallpapers, scriptModel.values.length);

        if (visible === 2)
            return 1;
        if (visible > 1 && visible % 2 === 0)
            return visible - 1;
        return visible;
    }

    implicitWidth: Math.min(numItems, pathView.count) * itemWidth

    ScriptModel {
        id: scriptModel

        readonly property string search: root.search.text.split(" ").slice(1).join(" ")

        values: {
            const all = Wallpapers.query(search);
            if (root.category === 1)
                return all.filter(w => Wallpapers.isLive(w.path));
            if (root.category === 2)
                return all.filter(w => !Wallpapers.isLive(w.path));
            return all;
        }
        onValuesChanged: pathView.currentIndex = search ? 0 : values.findIndex(w => w.path === Wallpapers.actualCurrent)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.small

        // Category filter: All / Animated (live video) / Static (image)
        RowLayout {
            id: filterRow

            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small

            TextButton {
                text: `All (${Wallpapers.list.length})`
                type: root.category === 0 ? TextButton.Filled : TextButton.Text
                onClicked: root.category = 0
            }

            TextButton {
                text: `Animated (${root.animatedCount})`
                type: root.category === 1 ? TextButton.Filled : TextButton.Text
                onClicked: root.category = 1
            }

            TextButton {
                text: `Static (${root.staticCount})`
                type: root.category === 2 ? TextButton.Filled : TextButton.Text
                onClicked: root.category = 2
            }
        }

        PathView {
            id: pathView

            Layout.fillWidth: true
            Layout.fillHeight: true

            Component.onCompleted: currentIndex = Wallpapers.list.findIndex(w => w.path === Wallpapers.actualCurrent)
            Component.onDestruction: Wallpapers.stopPreview()

            onCurrentItemChanged: {
                if (currentItem)
                    Wallpapers.preview((currentItem as WallpaperItem).modelData.path);
            }

            model: scriptModel

            pathItemCount: root.numItems
            cacheItemCount: 4

            snapMode: PathView.SnapToItem
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange

            delegate: WallpaperItem {
                screenState: root.screenState
            }

            path: Path {
                startY: pathView.height / 2

                PathAttribute {
                    name: "z"
                    value: 0
                }
                PathLine {
                    x: pathView.width / 2
                    relativeY: 0
                }
                PathAttribute {
                    name: "z"
                    value: 1
                }
                PathLine {
                    x: pathView.width
                    relativeY: 0
                }
            }

            CustomMouseArea {
                function onWheel(event: WheelEvent): void {
                    if (event.angleDelta.y > 0)
                        pathView.decrementCurrentIndex();
                    else if (event.angleDelta.y < 0)
                        pathView.incrementCurrentIndex();
                }

                anchors.fill: parent
            }
        }
    }
}
