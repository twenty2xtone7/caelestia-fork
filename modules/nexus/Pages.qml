import QtQuick
import Caelestia.Config
import qs.components
import qs.modules.nexus

Item {
    id: root

    required property NexusState nState

    property int lastPageIdx
    property int animOff
    property Item currentItem

    function loadPage(idx: int): void {
        if (currentItem)
            currentItem.destroy();

        const pageData = PageCompRegistry.pages[idx];
        if (!pageData) {
            console.warn("No page data for index", idx);
            return;
        }

        if (pageData.placeholder) {
            const incubator = PageCompRegistry.placeholderComponent.incubateObject(container, {
                nState: root.nState
            }, Qt.Asynchronous);

            const attach = () => {
                if (!incubator.object) {
                    console.warn("Failed to incubate placeholder", idx, incubator.errorString());
                    return;
                }
                incubator.object.anchors.fill = container;
                currentItem = incubator.object;
            };

            if (incubator.status === Component.Ready)
                attach();
            else
                incubator.onStatusChanged = status => {
                    if (status === Component.Ready)
                        attach();
                    else if (status === Component.Error)
                        console.warn("Failed to incubate placeholder", idx, incubator.errorString());
                };
            return;
        }

        // Resolve sub-page URLs to Components first, then pass them to
        // StackPage at creation time. StackPage pushes pages[0] in
        // Component.onCompleted, so assigning pages after incubation
        // would leave the view empty.
        const subPageComps = [];
        for (const subUrl of pageData.subPages) {
            const subComp = Qt.createComponent(Qt.resolvedUrl(subUrl));
            if (subComp.status === Component.Ready) {
                subPageComps.push(subComp);
            } else if (subComp.status === Component.Error) {
                console.warn("Failed to load", subUrl, subComp.errorString());
            } else {
                console.warn("Unexpected status loading", subUrl, subComp.status);
            }
        }

        if (subPageComps.length === 0) {
            console.warn("No sub-pages loaded for index", idx);
            return;
        }

        const stackComp = Qt.createComponent(Qt.resolvedUrl("common/StackPage.qml"));
        if (stackComp.status === Component.Error) {
            console.warn("Failed to load StackPage:", stackComp.errorString());
            return;
        }

        const createStack = () => {
            const incubator = stackComp.incubateObject(container, {
                nState: root.nState,
                pages: subPageComps
            }, Qt.Asynchronous);

            const attachStack = () => {
                if (!incubator.object) {
                    console.warn("Failed to incubate StackPage for index", idx, incubator.errorString());
                    return;
                }
                incubator.object.anchors.fill = container;
                currentItem = incubator.object;
            };

            if (incubator.status === Component.Ready)
                attachStack();
            else
                incubator.onStatusChanged = status => {
                    if (status === Component.Ready)
                        attachStack();
                    else if (status === Component.Error)
                        console.warn("Failed to incubate StackPage for index", idx, incubator.errorString());
                };
        };

        if (stackComp.status === Component.Ready)
            createStack();
        else
            stackComp.statusChanged.connect(status => {
                if (status === Component.Ready)
                    createStack();
                else if (status === Component.Error)
                    console.warn("Failed to load StackPage:", stackComp.errorString());
            });
    }

    Item {
        id: container

        objectName: "PageContainer"
        anchors.fill: parent
        layer.enabled: opacity < 1
        Component.onCompleted: root.loadPage(root.nState.currentPageIdx)
    }

    Connections {
        function onCurrentPageIdxChanged(): void {
            switchAnim.complete();
            root.animOff = root.Tokens.padding.extraLarge * (root.nState.currentPageIdx > root.lastPageIdx ? 1 : -1);
            switchAnim.start();
            root.lastPageIdx = root.nState.currentPageIdx;
        }

        target: root.nState
    }

    SequentialAnimation {
        id: switchAnim

        Anim {
            target: container
            property: "opacity"
            to: 0
            type: Anim.DefaultEffects
        }
        ScriptAction {
            script: root.loadPage(root.nState.currentPageIdx)
        }
        PropertyAction {
            target: container.anchors
            property: "topMargin"
            value: root.animOff
        }
        PropertyAction {
            target: container.anchors
            property: "bottomMargin"
            value: -root.animOff
        }
        ParallelAnimation {
            Anim {
                target: container
                property: "opacity"
                from: 0
                to: 1
                type: Anim.SlowEffects
            }
            Anim {
                target: container.anchors
                properties: "topMargin,bottomMargin"
                to: 0
                type: Anim.SlowEffects
            }
        }
    }
}
