import QtQuick
import QtQuick.Window

Window {
    id: floating

    width: handle.width + 8 + strip.implicitWidth
    height: 56
    color: "transparent"
    title: "Remcorder Keystrokes"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
    transientParent: null

    readonly property int bottomOffset: 140
    property bool pinned: false

    function place() {
        if (pinned) {
            const output = screen ?? (Qt.application.screens.length > 0 ? Qt.application.screens[0] : null)
            if (!output)
                return
            windowChrome.moveOverlay(floating, Math.round((output.width - width) / 2), 0, 0, bottomOffset)
            return
        }
        const target = Qt.application.screens.length > 0 ? Qt.application.screens[0] : null
        if (!target)
            return
        x = target.virtualX + Math.round((target.width - width) / 2)
        y = target.virtualY + target.height - height - bottomOffset
    }

    Component.onCompleted: {
        pinned = windowChrome.pinAbove(floating, WindowChrome.AnchorBottom | WindowChrome.AnchorLeft, 0, 0, 0, bottomOffset)
    }

    onVisibleChanged: {
        if (visible)
            place()
    }

    DragHandler {
        target: null
        onActiveChanged: {
            if (active)
                windowChrome.startMove(floating)
        }
    }

    Rectangle {
        id: handle
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 36
        radius: 9
        color: "#F2101013"
        border.width: 1
        border.color: backend.keystrokesVisible ? Theme.strokeHi : Theme.stroke
        opacity: handleHover.hovered || backend.keystrokesVisible ? 1 : 0.45

        Behavior on opacity { NumberAnimation { duration: 200 } }

        Glyph {
            anchors.centerIn: parent
            name: "keys"
            width: 15
            height: 15
            tint: handleHover.hovered ? Theme.ink : Theme.inkDim
        }

        HoverHandler { id: handleHover; cursorShape: Qt.SizeAllCursor }
    }

    KeystrokeStrip {
        id: strip
        anchors.left: handle.right
        anchors.leftMargin: 8
        anchors.top: parent.top
        anchors.bottom: parent.bottom
    }
}
