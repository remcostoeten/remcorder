import QtQuick

Rectangle {
    property Item target: parent

    anchors.fill: parent
    anchors.margins: -3
    radius: parent && parent.radius !== undefined ? parent.radius + 3 : 6
    color: "transparent"
    border.width: 2
    border.color: Theme.focusInk
    visible: target && target.activeFocus && target.visible
    z: 50
}
