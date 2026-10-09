import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../components"
import "../modules/trayWindows.js" as TrayWindows

Item {
    id: root

    readonly property int maxItemsPerPage: 5
    readonly property int itemCount: trayRepeater.count
    readonly property int pageItemCount: Math.min(itemCount, maxItemsPerPage)
    readonly property int pageCount: Math.max(1, Math.ceil(itemCount / maxItemsPerPage))
    property int currentPage: 0
    required property Item menuHost
    property var activeMenu: null
    // The host keeps the outgoing page alive until its bubble exit ends.
    property bool menuOpen: false
    // The delegate owning activeMenu. Tracked explicitly rather than looked up
    // by visibility: during a slide both the outgoing and incoming menus are
    // visible, so a visibility scan can return the wrong one.
    property var activeMenuOwner: null
    signal appActivated()

    // Query on click so focus history and window addresses are current.
    property var pendingActivation: null
    function activateApp(item): void {
        if (windowQuery.running)
            return;
        closeMenus();
        pendingActivation = item;
        appActivated();
        windowQuery.running = true;
    }

    Process {
        id: windowQuery
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                const item = root.pendingActivation;
                if (!item)
                    return;
                root.pendingActivation = null;
                let clients = [];
                try { clients = JSON.parse(text); } catch (error) {}
                const target = TrayWindows.findWindow(item, clients);
                if (target)
                    Hyprland.dispatch(Hyprland.usingLua
                        ? 'hl.dsp.focus({ window = "address:' + target.address + '" })'
                        : "focuswindow address:" + target.address);
                else if (!item.onlyMenu)
                    item.activate();
            }
        }
    }

    // Visible pages follow whichever menu is currently open.
    function syncPageTo(index: int): void {
        const page = Math.max(0, Math.min(pageCount - 1,
                                        Math.floor(index / maxItemsPerPage)));
        if (page !== currentPage)
            currentPage = page;
    }

    function closeMenus(except): void {
        if (activeMenu && activeMenu !== except) {
            menuOpen = false;
        }
    }

    function finishMenuClose(): void {
        if (menuOpen)
            return;
        if (activeMenu)
            activeMenu.visible = false;
        activeMenu = null;
        activeMenuOwner = null;
    }

    // Menus are full-width pages inside the host, so switching apps becomes a
    // horizontal slide: the outgoing menu leaves the way the incoming one
    // entered, and the new menu lands exactly where the old one was.
    function slideMenus(from, to, dir): void {
        if (!from || !to || from === to)
            return;
        const w = menuHost.width;
        // Anything still visible from an interrupted slide would overlap the
        // incoming menu, so retire it immediately.
        for (let i = 0; i < itemCount; ++i) {
            const item = trayRepeater.itemAt(i);
            if (item && item.menuPage && item.menuPage !== from && item.menuPage !== to)
                item.menuPage.visible = false;
        }
        from.slideStop();
        to.slideStop();
        // Both pages share the taller menu's height for the duration of the
        // slide. Otherwise the host resizes mid-animation and the incoming menu
        // jumps to a different height while it is already moving.
        const h = Math.max(from.implicitHeight, to.implicitHeight);
        from.slideHeight = h;
        to.slideHeight = h;
        from.x = 0;
        to.x = dir * w;
        to.z = 1;
        from.z = 0;
        from.slideTarget = -dir * w;
        to.slideTarget = 0;
        from.slideStart();
        to.slideStart();
    }

    function changePage(delta): void {
        if (pageCount <= 1 || delta === 0)
            return;
        currentPage = (currentPage + (delta > 0 ? 1 : -1) + pageCount) % pageCount;
    }

    function wheelDelta(wheel): int {
        let delta = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)
                    ? wheel.angleDelta.x : wheel.angleDelta.y;
        if (delta === 0)
            delta = Math.abs(wheel.pixelDelta.x) > Math.abs(wheel.pixelDelta.y)
                    ? wheel.pixelDelta.x : wheel.pixelDelta.y;
        return delta;
    }

    function changePageFromWheel(wheel): void {
        const delta = wheelDelta(wheel);
        if (delta !== 0)
            changePage(delta < 0 ? 1 : -1);
    }

    // Which way the incoming menu should slide, derived from where the two
    // tray icons actually sit on screen rather than from index arithmetic, so
    // the animation always follows the pointer from icon to icon.
    function slideDirection(fromItem, toItem): int {
        if (!fromItem || fromItem === toItem)
            return 1;
        const a = root.mapFromItem(fromItem, 0, 0).x;
        const b = root.mapFromItem(toItem, 0, 0).x;
        return b >= a ? 1 : -1;
    }

    // Clamp after the derived page count updates. The item-count signal can
    // arrive while pageCount still contains the previous number of pages.
    onPageCountChanged: currentPage = Math.max(0, Math.min(currentPage, pageCount - 1))

    visible: itemCount > 0
    // Only the pebble participates in the date row's alignment. The dots
    // are an overlay below it and never alter the tray's horizontal footprint.
    implicitWidth: trayRow.width + 8
    implicitHeight: trayRow.height + (pageDots.visible ? pageDots.implicitHeight + 5 : 0)
    width: implicitWidth
    height: implicitHeight

    // The app tiles live on this pebble; the page indicators deliberately
    // sit below it on the transparent parent item.
    Rectangle {
        id: pebble
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: trayRow.width + 8
        height: trayRow.height
        radius: Theme.radius
        color: Theme.popupSurface0
    }

    Column {
        id: trayColumn
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0

        RowLayout {
            id: trayRow
            spacing: 2
            // Keep every page the width of a five-icon tray, including a
            // partially filled final page.
            width: root.pageItemCount * 28 + Math.max(0, root.pageItemCount - 1) * spacing

            Repeater {
            id: trayRepeater
            model: SystemTray.items

            delegate: Rectangle {
            id: trayButton
            required property var modelData
            required property int index
            property var menuStack: []
            readonly property Item menuPage: menuPopup
            Component.onDestruction: {
                if (root.activeMenu === menuPopup) {
                    root.activeMenu = null;
                    root.activeMenuOwner = null;
                    root.menuOpen = false;
                }
            }

            visible: index >= root.currentPage * root.maxItemsPerPage
                     && index < (root.currentPage + 1) * root.maxItemsPerPage
            Layout.alignment: Qt.AlignVCenter
            width: 28
            height: 30
            color: "transparent"

            // Keep the full tile clickable while giving its active treatment a
            // slightly tighter footprint around the icon.
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Theme.radius
                // No hover treatment: the tray only highlights while its own
                // menu is open, so the bar stays visually quiet at rest.
                color: root.menuOpen && root.activeMenu === menuPopup
                    ? Theme.popupSurface1 : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: 19
                source: trayButton.modelData.icon
                asynchronous: true
            }

            QsMenuOpener {
                id: menuOpener
                menu: trayButton.modelData.menu
            }

            function openMenu(): bool {
                if (root.activeMenu === menuPopup) {
                    root.menuOpen = true;
                    return true;
                }
                if (!modelData.hasMenu)
                    return false;
                const previous = root.activeMenu;
                const previousItem = root.activeMenuOwner;
                root.closeMenus(previous);
                menuStack = [];
                menuOpener.menu = modelData.menu;
                menuList.resetScroll();
                root.activeMenuOwner = trayButton;
                root.activeMenu = menuPopup;
                menuPopup.visible = true;
                root.menuOpen = true;
                root.syncPageTo(index);
                root.slideMenus(previous, menuPopup,
                                root.slideDirection(previousItem, trayButton));
                return true;
            }

            function openSubmenu(entry) {
                const stack = menuStack.slice();
                stack.push(menuOpener.menu);
                menuStack = stack;
                menuOpener.menu = entry;
                menuList.resetScroll();
            }

            function goBack() {
                if (menuStack.length === 0)
                    return;
                const stack = menuStack.slice();
                menuOpener.menu = stack.pop();
                menuStack = stack;
                menuList.resetScroll();
            }

            // Heights mirror the delegate sizes (32 for an entry, 9 for a
            // separator) plus the row spacing, so the popup never crops the
            // last item.
            function menuContentHeight() {
                let total = 0;
                const entries = menuOpener.children.values;
                for (let i = 0; i < entries.length; ++i)
                    total += (entries[i] && entries[i].isSeparator) ? 9 : 32;
                if (entries.length > 0)
                    total += 2 * (entries.length - 1);
                return total;
            }

            MouseArea {
                id: trayMouse
                anchors.fill: parent
                hoverEnabled: false
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor

                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) {
                        root.closeMenus();
                        trayButton.modelData.secondaryActivate();
                    } else if (mouse.button === Qt.RightButton) {
                        // Right click opens the item's menu; without one it
                        // behaves like a left click, which dismisses the menu.
                        if (!trayButton.openMenu())
                            root.closeMenus();
                    } else {
                        root.activateApp(trayButton.modelData);
                    }
                }

                onWheel: wheel => {
                    // With several pages, wheel gestures navigate the tray.
                    // A single-page tray retains each app's normal scroll action.
                    if (root.pageCount > 1) {
                        root.changePageFromWheel(wheel);
                    } else {
                        const horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y);
                        const delta = horizontal ? wheel.angleDelta.x : wheel.angleDelta.y;
                        trayButton.modelData.scroll(delta, horizontal);
                    }
                    wheel.accepted = true;
                }
            }

            Item {
                id: menuPopup
                parent: root.menuHost
                width: parent.width
                visible: false
                enabled: root.menuOpen && root.activeMenu === menuPopup
                clip: true
                // No x binding: the slide assigns x imperatively, and a
                // constant binding here would only invite the two to fight.
                // Destination the slide animation runs to; anything that ends
                // away from zero is a menu on its way out.
                property real slideTarget: 0
                // Non-zero only while this menu takes part in a slide; both
                // pages share one height so the host does not resize mid-slide.
                property real slideHeight: 0
                implicitHeight: Math.min(root.menuHost.maximumMenuHeight,
                                         Math.max(80, trayButton.menuContentHeight() + 49
                                                  + (trayButton.menuStack.length > 0 ? 4 : 0)))
                height: slideHeight > 0 ? slideHeight : implicitHeight

                onVisibleChanged: {
                    if (!visible) {
                        // Never leave a hidden menu parked off-screen, or the
                        // next open would start at the wrong offset.
                        slideAnim.stop();
                        x = 0;
                        slideHeight = 0;
                        if (root.activeMenu === menuPopup) {
                            root.activeMenu = null;
                            root.activeMenuOwner = null;
                        }
                    }
                }

                function slideStart(): void {
                    slideAnim.from = x;
                    slideAnim.to = slideTarget;
                    slideAnim.start();
                }

                function slideStop(): void {
                    slideAnim.stop();
                    x = 0;
                }

                NumberAnimation {
                    id: slideAnim
                    target: menuPopup
                    property: "x"
                    duration: 155
                    easing.type: Easing.OutCubic

                    onFinished: {
                        // Landing away from the origin means this page slid
                        // out; retire it once it is fully gone.
                        if (menuPopup.x !== 0) {
                            menuPopup.visible = false;
                            menuPopup.x = 0;
                        }
                        // Exactly one page keeps the shared slide height: the
                        // one that landed on the origin.
                        if (menuPopup.x === 0)
                            menuPopup.slideHeight = 0;
                    }
                }

                Item {
                    anchors.fill: parent
                    // Keep the text on the same filtered layer while visible
                    // so starting/stopping a slide does not change rasterization.
                    layer.enabled: menuPopup.visible
                    layer.smooth: true
                    layer.effect: DirectionalBlur {
                        angle: 0
                        samples: 17
                        // The squared envelope eases into and out of a short
                        // blur, keeping letter strokes stable at both ends.
                        length: slideAnim.running ? 2.5 * Math.pow(Math.sin(Math.PI * Math.min(1,
                            Math.abs(menuPopup.x) / Math.max(1, menuPopup.width))), 2) : 0
                        transparentBorder: true
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            spacing: 6

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                visible: trayButton.menuStack.length > 0
                                radius: Theme.radius
                                color: backMouse.containsMouse ? Theme.popupSurface1 : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "arrow_back"
                                    color: Theme.colors.blue
                                    font.family: Theme.iconFamily
                                    font.pixelSize: 18
                                }
                                MouseArea {
                                    id: backMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: trayButton.goBack()
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: trayButton.modelData.title || trayButton.modelData.tooltipTitle || trayButton.modelData.id
                                elide: Text.ElideRight
                                color: Theme.colors.text
                                font.family: Theme.textFamily
                                font.pixelSize: 11
                                font.bold: true
                            }

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: Theme.radius
                                color: closeMouse.containsMouse ? Theme.popupSurface1 : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "close"
                                    color: Theme.colors.text
                                    font.family: Theme.iconFamily
                                    font.pixelSize: 18
                                }
                                MouseArea {
                                    id: closeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.closeMenus()
                                }
                            }
                        }

                        // Separator between the back row and the menu entries.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            visible: trayButton.menuStack.length > 0
                            color: Theme.popupSurface0
                        }

                        ListView {
                            id: menuList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            model: menuOpener.children
                            boundsBehavior: Flickable.StopAtBounds
                            function resetScroll(): void {
                                scrollAnimation.stop();
                                contentY = originY;
                            }
                            onModelChanged: resetScroll()
                            onMovementStarted: scrollAnimation.stop()

                            NumberAnimation {
                                id: scrollAnimation
                                target: menuList
                                property: "contentY"
                                duration: 180
                                easing.type: Easing.OutCubic
                            }

                            MouseArea {
                                anchors.fill: parent
                                z: 1
                                acceptedButtons: Qt.NoButton
                                onWheel: wheel => {
                                    const delta = wheel.pixelDelta.y !== 0
                                                ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * 60;
                                    const previous = scrollAnimation.running ? scrollAnimation.to : menuList.contentY;
                                    scrollAnimation.stop();
                                    scrollAnimation.from = menuList.contentY;
                                    scrollAnimation.to = Math.max(menuList.originY,
                                        Math.min(menuList.originY + Math.max(0, menuList.contentHeight - menuList.height),
                                                 previous - delta));
                                    scrollAnimation.start();
                                    wheel.accepted = true;
                                }
                            }

                            delegate: Item {
                                id: menuEntry
                                required property var modelData
                                width: menuList.width
                                height: modelData.isSeparator ? 9 : 32

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 1
                                    visible: menuEntry.modelData.isSeparator
                                    color: Theme.popupSurface1
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radius
                                    visible: !menuEntry.modelData.isSeparator
                                    color: entryMouse.containsMouse && menuEntry.modelData.enabled
                                           ? Theme.popupSurface1 : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Item {
                                            width: 18
                                            height: 18

                                            IconImage {
                                                anchors.fill: parent
                                                source: menuEntry.modelData.icon
                                                visible: source.toString().length > 0
                                                asynchronous: true
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                visible: menuEntry.modelData.buttonType !== QsMenuButtonType.None
                                                         && menuEntry.modelData.icon.toString().length === 0
                                                text: menuEntry.modelData.checkState === Qt.Checked ? "check" : ""
                                                color: Theme.colors.mauve
                                                font.family: Theme.iconFamily
                                                font.pixelSize: 15
                                            }
                                        }

                                        Text {
                                            font.family: Theme.textFamily
                                            Layout.fillWidth: true
                                            text: menuEntry.modelData.text
                                            color: menuEntry.modelData.enabled
                                                   ? Theme.colors.text : Theme.popupSurface2
                                            elide: Text.ElideRight
                                            font.pixelSize: 11
                                        }

                                        Text {
                                            visible: menuEntry.modelData.hasChildren
                                            text: "chevron_right"
                                            color: Theme.colors.textDim
                                            font.family: Theme.iconFamily
                                            font.pixelSize: 17
                                        }
                                    }

                                    MouseArea {
                                        id: entryMouse
                                        anchors.fill: parent
                                        enabled: menuEntry.modelData.enabled
                                        hoverEnabled: true
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (menuEntry.modelData.hasChildren) {
                                                trayButton.openSubmenu(menuEntry.modelData);
                                            } else {
                                                root.closeMenus();
                                                menuEntry.modelData.triggered();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }
            }

        }

    }

    Row {
        id: pageDots
        anchors.top: pebble.bottom
        anchors.topMargin: 5
        anchors.horizontalCenter: pebble.horizontalCenter
        visible: root.pageCount > 1
        spacing: 4

        Repeater {
            model: root.pageCount

            delegate: Rectangle {
                required property int index
                width: index === root.currentPage ? 10 : 5
                height: 5
                radius: Theme.radius
                color: index === root.currentPage ? Theme.colors.text : Theme.colors.overlay0

                Behavior on width { NumberAnimation { duration: 120 } }
                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -3
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.currentPage = parent.index
                    onWheel: wheel => {
                        root.changePageFromWheel(wheel);
                        wheel.accepted = true;
                    }
                }
            }
        }
    }

    // Keep page scrolling independent of the delegate currently under the
    // pointer. No mouse buttons are accepted, so tray icon clicks pass through.
    MouseArea {
        anchors.fill: pebble
        acceptedButtons: Qt.NoButton
        z: 1
        onWheel: wheel => {
            root.changePageFromWheel(wheel);
            wheel.accepted = true;
        }
    }
}
