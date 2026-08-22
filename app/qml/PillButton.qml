import QtQuick
import QtQuick.Controls

Rectangle {
    id: button

    property string glyph: ""
    property string hint: ""
    property color accent: Theme.ink

    signal activated()

    width: 30
    height: 30
    radius: 9
    color: hover.hovered ? Theme.surfaceTop : "transparent"

    Behavior on color { ColorAnimation { duration: 120 } }

    Glyph {
        anchors.centerIn: parent
        name: button.glyph
        width: 14
        height: 14
        tint: hover.hovered ? button.accent : Theme.inkDim

        Behavior on tint { ColorAnimation { duration: 120 } }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: button.activated() }

    ToolTip.visible: hover.hovered && hint.length > 0
    ToolTip.text: hint
    ToolTip.delay: 400

    Accessible.role: Accessible.Button
    Accessible.name: hint
    Accessible.onPressAction: button.activated()

    scale: hover.hovered ? 1.06 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
}
