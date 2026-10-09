import QtQuick 2.15
import QtQuick.Templates 2.15 as T
T.ComboBox {
    id: control
    implicitWidth: Math.max(160, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    padding: 8
    leftPadding: 10
    rightPadding: 30
    hoverEnabled: true
    delegate: ItemDelegate {
        width: control.width
        text: control.textRole ? (Array.isArray(control.model) ? modelData[control.textRole] : model[control.textRole]) : modelData
        highlighted: control.highlightedIndex === index
        font: control.font
    }
    contentItem: TextInput {
        text: control.editable ? control.editText : control.displayText
        font: control.font
        color: control.enabled ? Theme.text : Theme.disabled.text
        selectionColor: Theme.primary
        selectedTextColor: Theme.primaryText
        verticalAlignment: TextInput.AlignVCenter
        readOnly: !control.editable
        autoScroll: control.editable
        inputMethodHints: control.inputMethodHints
        validator: control.validator
        clip: true
    }
    indicator: Text {
        x: control.mirrored ? 10 : control.width - width - 10
        y: (control.height - height) / 2
        text: "⌄"
        font.pixelSize: 16
        color: Theme.text
    }
    background: Rectangle {
        radius: 8
        color: control.editable ? Theme.base : control.hovered || control.down ? Theme.hover : Theme.button
        border.color: control.visualFocus ? Theme.primary : Theme.border
    }
    popup: Popup {
        y: control.height + 4
        width: control.width
        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
        padding: 6
        contentItem: ListView {
            clip: true
            implicitHeight: Math.min(contentHeight, 280)
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            highlightMoveDuration: 0
        }
    }
}
