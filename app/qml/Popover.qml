import QtQuick
import QtQuick.Controls

Popup {
    id: pop

    property Item anchorItem: null
    property string heading: ""

    parent: anchorItem
    x: anchorItem ? Math.round((anchorItem.width - width) / 2) : 0
    y: anchorItem ? anchorItem.height + 8 : 0
    margins: 12
    padding: 12
    popupType: Popup.Window
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    onClosed: {
        if (anchorItem && anchorItem.visible)
            anchorItem.forceActiveFocus(Qt.PopupFocusReason)
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 }
        NumberAnimation {
            property: "scale"
            from: 0.96
            to: 1
            duration: 170
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 }
        NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: 100 }
    }

    background: Rectangle {
        radius: 13
        color: Theme.surfaceHi
        border.width: 1
        border.color: "#31313A"

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 13
            anchors.rightMargin: 13
            anchors.topMargin: 1
            height: 1
            color: "#14FFFFFF"
        }
    }
}
