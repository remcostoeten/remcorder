import QtQuick

Rectangle {
    radius: 12
    color: Theme.surface
    border.width: 1
    border.color: Theme.stroke

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: parent.radius
        anchors.rightMargin: parent.radius
        anchors.topMargin: 1
        height: 1
        color: Theme.specular
    }
}
