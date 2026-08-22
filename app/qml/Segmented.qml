import QtQuick

Rectangle {
    id: seg

    property var options: []
    property string current: ""
    signal picked(string value)

    readonly property int activeIndex: {
        for (let i = 0; i < options.length; ++i) {
            if (options[i].value === current)
                return i
        }
        return 0
    }
    readonly property real cellWidth: options.length > 0 ? (width - 8) / options.length : 0

    implicitHeight: 38
    radius: 11
    color: Theme.canvasLift
    border.width: 1
    border.color: Theme.stroke

    Rectangle {
        width: seg.cellWidth
        height: seg.height - 8
        x: 4 + seg.activeIndex * seg.cellWidth
        y: 4
        radius: 8
        color: Theme.surfaceTop
        border.width: 1
        border.color: Theme.strokeHi

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 7
            anchors.rightMargin: 7
            anchors.topMargin: 1
            height: 1
            color: "#14FFFFFF"
        }

        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    Row {
        anchors.fill: parent
        anchors.margins: 4

        Repeater {
            model: seg.options

            delegate: Item {
                id: cell
                required property var modelData
                required property int index

                readonly property bool active: seg.activeIndex === index

                width: seg.cellWidth
                height: seg.height - 8

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: cell.modelData.glyph !== undefined
                        name: cell.modelData.glyph !== undefined ? cell.modelData.glyph : ""
                        width: 14
                        height: 14
                        tint: cell.active ? Theme.ink : hover.hovered ? Theme.inkDim : Theme.inkFaint

                        Behavior on tint { ColorAnimation { duration: 120 } }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cell.modelData.label
                        color: cell.active ? Theme.ink : hover.hovered ? Theme.ink : Theme.inkDim
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: cell.active ? Font.DemiBold : Font.Medium

                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }

                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: seg.picked(cell.modelData.value) }
            }
        }
    }
}
