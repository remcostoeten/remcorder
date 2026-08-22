import QtQuick

Item {
    id: meter

    property real level: 0
    property real peak: 0
    property int bars: 28

    readonly property real gap: 2

    implicitHeight: 16
    implicitWidth: 120

    Row {
        anchors.fill: parent
        spacing: meter.gap

        Repeater {
            model: meter.bars

            delegate: Rectangle {
                id: bar
                required property int index

                readonly property real position: (index + 0.5) / meter.bars
                readonly property bool lit: meter.level >= position
                readonly property bool atPeak: meter.peak > 0.02
                    && Math.abs(meter.peak - position) < 0.5 / meter.bars

                width: Math.max(1, (meter.width - meter.gap * (meter.bars - 1)) / meter.bars)
                height: meter.height
                radius: 1
                color: atPeak
                    ? Theme.ink
                    : lit
                    ? (position > 0.9 ? Theme.signal : position > 0.72 ? Theme.amber : Theme.successInk)
                    : Theme.surfaceTop
                opacity: atPeak ? 0.9 : lit ? 1 : 0.55

                Behavior on color { ColorAnimation { duration: 90 } }
                Behavior on opacity { NumberAnimation { duration: 90 } }
            }
        }
    }
}
