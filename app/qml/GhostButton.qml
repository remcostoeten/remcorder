import QtQuick
import QtQuick.Controls

Button {
    id: control

    property color fill: Theme.surfaceHi
    property color textColor: Theme.ink
    property color accentColor: Theme.focusBlue
    property string glyph: ""
    property bool bordered: true

    implicitHeight: 34
    leftPadding: 12
    rightPadding: 12
    font.family: Theme.sans
    font.pixelSize: 13
    font.weight: Font.Medium
    hoverEnabled: true

    contentItem: Item {
        implicitWidth: ghostLabel.implicitWidth
        implicitHeight: ghostLabel.implicitHeight

        Row {
            id: ghostLabel
            anchors.centerIn: parent
            spacing: control.text.length > 0 && control.glyph.length > 0 ? 7 : 0

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.glyph.length > 0
                name: control.glyph
                width: 14
                height: 14
                tint: control.enabled ? control.textColor : Theme.inkFaint
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.text.length > 0
                text: control.text
                color: control.enabled ? control.textColor : Theme.inkFaint
                opacity: control.enabled ? 1 : 0.55
                font: control.font
            }
        }
    }

    background: Rectangle {
        radius: 9
        color: control.down
            ? Qt.darker(control.fill, 1.3)
            : control.hovered ? Theme.surfaceTop : control.fill
        border.width: 1
        border.color: control.activeFocus
            ? control.accentColor
            : control.hovered ? Theme.strokeHi : control.bordered ? Theme.stroke : "transparent"

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 1
            height: 1
            color: Theme.specular
            visible: control.enabled && !control.down && control.bordered
        }

        Behavior on color { ColorAnimation { duration: 130 } }
        Behavior on border.color { ColorAnimation { duration: 130 } }
    }

    scale: down ? 0.98 : 1
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
