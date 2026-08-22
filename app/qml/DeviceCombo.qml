import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ComboBox {
    id: combo

    implicitHeight: 36
    textRole: "name"
    valueRole: "value"
    font.family: Theme.sans
    font.pixelSize: 13
    hoverEnabled: true

    contentItem: Text {
        leftPadding: 12
        rightPadding: 32
        text: combo.displayText
        color: Theme.ink
        font: combo.font
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: 9
        color: combo.hovered ? Theme.surfaceHi : Theme.canvasLift
        border.width: 1
        border.color: combo.activeFocus
            ? Theme.focusBlue
            : combo.hovered ? Theme.strokeHi : Theme.stroke

        Behavior on color { ColorAnimation { duration: 130 } }
        Behavior on border.color { ColorAnimation { duration: 130 } }
    }

    indicator: Glyph {
        x: combo.width - width - 10
        y: (combo.height - height) / 2
        width: 13
        height: 13
        name: "chevron"
        tint: Theme.inkDim
        rotation: combo.popup.visible ? 180 : 0

        Behavior on rotation { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    }

    popup: Popup {
        y: combo.height + 5
        width: combo.width
        implicitHeight: Math.min(contentItem.implicitHeight + 10, 260)
        padding: 5

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 110 }
            NumberAnimation {
                property: "scale"
                from: 0.97
                to: 1
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 }
        }

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: combo.popup.visible ? combo.delegateModel : null
            currentIndex: combo.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }

        background: Rectangle {
            radius: 11
            color: Theme.surfaceHi
            border.width: 1
            border.color: "#2E2E35"
        }
    }

    delegate: ItemDelegate {
        id: option
        required property var model
        required property int index

        width: combo.width - 10
        height: 34
        highlighted: combo.highlightedIndex === index

        contentItem: RowLayout {
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: option.model.name
                color: Theme.ink
                font: combo.font
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            Glyph {
                visible: combo.currentIndex === option.index
                Layout.preferredWidth: 13
                Layout.preferredHeight: 13
                name: "check"
                tint: Theme.focusInk
            }
        }

        background: Rectangle {
            radius: 7
            color: option.highlighted ? Theme.surfaceTop : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }
}
