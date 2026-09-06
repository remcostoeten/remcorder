import QtQuick

Rectangle {
    id: chip

    property string glyph: ""
    property string label: ""
    property bool checkable: true
    property bool checked: false
    property bool hasMenu: false
    property bool menuOpen: false
    property color tint: Theme.focusBlue

    signal toggled()
    signal menuRequested()

    readonly property bool split: checkable && hasMenu
    readonly property bool lit: checkable && checked
    readonly property real menuWidth: hasMenu ? (split ? 24 : 16) : 0

    implicitHeight: 42
    implicitWidth: bodyRow.implicitWidth + 22 + menuWidth
    radius: 10
    color: lit
        ? Theme.tintSurface(tint)
        : bodyHover.hovered || menuHover.hovered || menuOpen ? Theme.surfaceHi : Theme.canvasLift
    border.width: 1
    border.color: lit
        ? Theme.tintBorder(tint)
        : bodyHover.hovered || menuHover.hovered || menuOpen ? Theme.strokeHi : Theme.stroke

    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on border.color { ColorAnimation { duration: 140 } }

    activeFocusOnTab: true
    Accessible.role: checkable ? Accessible.CheckBox : Accessible.Button
    Accessible.checkable: checkable
    Accessible.checked: lit

    function activate() {
        if (checkable)
            toggled()
        else if (hasMenu)
            menuRequested()
    }

    Keys.onSpacePressed: activate()
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed: activate()
    Keys.onDownPressed: event => {
        if (hasMenu) {
            menuRequested()
            event.accepted = true
        }
    }

    FocusRing {}

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 1
        height: 1
        color: Theme.specular
        visible: !chip.lit
    }

    Item {
        id: bodyArea

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.rightMargin: chip.split ? chip.menuWidth : 0

        Row {
            id: bodyRow
            anchors.centerIn: parent
            spacing: 7

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                name: chip.glyph
                width: 15
                height: 15
                tint: chip.lit
                    ? chip.tint
                    : bodyHover.hovered ? Theme.inkDim : Theme.inkFaint

                Behavior on tint { ColorAnimation { duration: 140 } }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: chip.lit ? Theme.ink : bodyHover.hovered ? Theme.ink : Theme.inkDim
                font.family: Theme.sans
                font.pixelSize: 13
                font.weight: chip.lit ? Font.DemiBold : Font.Medium

                Behavior on color { ColorAnimation { duration: 140 } }
            }

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.hasMenu && !chip.split
                name: "chevron"
                width: 11
                height: 11
                tint: Theme.inkFaint
                rotation: chip.menuOpen ? 180 : 0

                Behavior on rotation { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
            }
        }

        HoverHandler { id: bodyHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.activate() }
    }

    Rectangle {
        anchors.right: menuArea.left
        anchors.verticalCenter: parent.verticalCenter
        visible: chip.split
        width: 1
        height: parent.height - 14
        color: chip.lit ? Theme.tintBorder(chip.tint) : Theme.stroke
    }

    Item {
        id: menuArea

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: chip.split ? chip.menuWidth : 0
        visible: chip.split

        Glyph {
            anchors.centerIn: parent
            name: "chevron"
            width: 11
            height: 11
            tint: menuHover.hovered || chip.menuOpen ? Theme.ink : Theme.inkFaint
            rotation: chip.menuOpen ? 180 : 0

            Behavior on tint { ColorAnimation { duration: 130 } }
            Behavior on rotation { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        }

        HoverHandler { id: menuHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.menuRequested() }
    }
}
