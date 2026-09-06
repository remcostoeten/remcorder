import QtQuick
import QtQuick.Controls

Rectangle {
    id: button

    property string glyph: ""
    property string hint: ""
    property string label: ""
    property color accent: Theme.ink
    property bool active: false

    signal activated()

    readonly property bool labelled: label.length > 0

    width: labelled ? content.implicitWidth + 18 : 30
    height: 30
    radius: 9
    color: hover.hovered || labelled ? Theme.surfaceTop : "transparent"

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            name: button.glyph
            width: 14
            height: 14
            tint: hover.hovered || button.active ? button.accent : Theme.inkDim

            Behavior on tint { ColorAnimation { duration: 120 } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.labelled
            text: button.label
            color: button.accent
            font.family: Theme.sans
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: button.activated() }

    ToolTip.visible: hover.hovered && hint.length > 0
    ToolTip.text: hint
    ToolTip.delay: 400

    activeFocusOnTab: true
    Keys.onSpacePressed: button.activated()
    Keys.onReturnPressed: button.activated()
    Keys.onEnterPressed: button.activated()

    FocusRing {}

    Accessible.role: Accessible.Button
    Accessible.name: hint
    Accessible.onPressAction: button.activated()

    scale: hover.hovered ? 1.06 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
}
