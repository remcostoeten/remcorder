import QtQuick
import QtQuick.Controls

Button {
    id: primary

    property color tint: Theme.signal
    property string glyph: ""

    implicitHeight: 46
    font.family: Theme.sans
    font.pixelSize: 14
    font.weight: Font.DemiBold
    hoverEnabled: true

    contentItem: Item {
        implicitWidth: primaryLabel.implicitWidth
        implicitHeight: primaryLabel.implicitHeight

        Row {
            id: primaryLabel
            anchors.centerIn: parent
            spacing: 9

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                visible: primary.glyph.length > 0
                name: primary.glyph
                width: 15
                height: 15
                tint: primary.enabled ? "#FFFFFF" : Theme.inkFaint
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: primary.text
                color: primary.enabled ? "#FFFFFF" : Theme.inkFaint
                font: primary.font
            }
        }
    }

    background: Item {
        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 20
            height: parent.height - 2
            radius: 18
            color: primary.tint
            opacity: primary.enabled ? (primary.hovered ? 0.3 : 0.15) : 0

            Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        Rectangle {
            anchors.fill: parent
            radius: 11
            color: primary.enabled
                ? (primary.down
                    ? Qt.darker(primary.tint, 1.2)
                    : primary.hovered ? Qt.lighter(primary.tint, 1.12) : primary.tint)
                : Theme.surfaceHi
            border.width: 1
            border.color: primary.enabled ? Qt.lighter(primary.tint, 1.3) : Theme.stroke

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 1
                height: 1
                color: "#2EFFFFFF"
                visible: primary.enabled && !primary.down
            }

            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    scale: down ? 0.99 : 1
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
