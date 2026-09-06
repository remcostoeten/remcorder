import QtQuick
import QtQuick.Controls

Button {
    id: chromeButton

    property color hoverFill: Theme.surfaceHi
    property color hoverInk: Theme.ink
    property string glyph: ""
    property bool tabbable: false

    implicitWidth: 28
    implicitHeight: 28
    hoverEnabled: true
    focusPolicy: tabbable ? Qt.TabFocus : Qt.NoFocus

    contentItem: Item {
        Glyph {
            anchors.centerIn: parent
            name: chromeButton.glyph
            width: 14
            height: 14
            tint: chromeButton.hovered ? chromeButton.hoverInk : Theme.inkFaint

            Behavior on tint { ColorAnimation { duration: 120 } }
        }
    }

    background: Rectangle {
        radius: 8
        color: chromeButton.down
            ? Qt.darker(chromeButton.hoverFill, 1.2)
            : chromeButton.hovered ? chromeButton.hoverFill : "transparent"

        border.width: chromeButton.activeFocus ? 2 : 0
        border.color: Theme.focusInk

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
