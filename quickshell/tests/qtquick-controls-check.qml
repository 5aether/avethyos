import QtQuick 2.15
import QtQuick.Controls

ApplicationWindow {
    id: window
    width: 720
    height: 640
    visible: true
    function showMenu() { menu.open() }
    function showTooltip() { menu.close(); tooltip.open() }
    Pane {
        anchors.fill: parent
        Column {
            spacing: 12
            Button { objectName: "button"; text: "Apply"; highlighted: true }
            ToolButton { objectName: "tool"; text: "Active"; checked: true }
            TextField { objectName: "field"; text: "Wallpaper theme" }
            CheckBox { objectName: "checkbox"; text: "Enabled"; checked: true }
            RadioButton { objectName: "radio"; text: "Selected"; checked: true }
            Switch { objectName: "switch"; text: "Enabled"; checked: true }
            Slider { objectName: "slider"; value: 0.65 }
            ProgressBar { objectName: "progress"; value: 0.65 }
            ItemDelegate { objectName: "selected"; text: "Home"; highlighted: true }
            Frame { Label { text: "Transparent frame" } }
            ComboBox { objectName: "combo"; model: ["Wallpaper", "Light", "Dark"]; editable: true }
            TabButton { text: "Files"; checked: true }
            ScrollBar { width: 200; orientation: Qt.Horizontal; size: 0.3; active: true }
        }
        Menu {
            id: menu
            objectName: "menu"
            x: 320
            y: 40
            Component.onCompleted: itemAt(3).objectName = "menuMore"
            MenuItem { objectName: "menuOpen"; text: "Open" }
            MenuItem { objectName: "menuChecked"; text: "Pinned"; checkable: true; checked: true }
            MenuSeparator { objectName: "menuSeparator" }
            Menu {
                objectName: "submenu"
                title: "More"
                MenuItem { text: "Properties" }
            }
            MenuItem { objectName: "menuDisabled"; text: "Unavailable"; enabled: false }
        }
        Button {
            id: tooltipAnchor
            objectName: "tooltipAnchor"
            x: 350
            y: 350
            text: "Details"
            ToolTip { id: tooltip; objectName: "tooltip"; text: "Wallpaper colors" }
        }
    }
}
