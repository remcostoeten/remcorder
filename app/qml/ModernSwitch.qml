import QtQuick
import QtQuick.Controls

Switch {
    id: toggle

    property color tint: Theme.signal

    implicitWidth: 42
    implicitHeight: 24
    hoverEnabled: true

    indicator: Rectangle {
        implicitWidth: 40
        implicitHeight: 22
        x: toggle.width - width
        y: (toggle.height - height) / 2
        radius: 11
        color: toggle.checked ? toggle.tint : Theme.surfaceHi
        border.width: 1
        border.color: toggle.activeFocus
            ? Theme.ink
            : toggle.checked ? Qt.lighter(toggle.tint, 1.25) : Theme.strokeHi

        Rectangle {
            x: toggle.checked ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: toggle.checked ? "#FFFFFF" : "#8A8A94"
            scale: toggle.hovered ? 1.06 : 1

            Behavior on x { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on scale { NumberAnimation { duration: 120 } }
        }

        Behavior on color { ColorAnimation { duration: 150 } }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
