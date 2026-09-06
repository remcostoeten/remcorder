import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell

Window {
    id: keys

    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom
    LayerShell.Window.margins.bottom: 96
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.scope: "remcorder-overlay"

    property string statePath: ""
    property real holdSeconds: 2.5
    property double updatedAt: 0
    property double nowMs: 0
    property bool faded: nowMs - updatedAt > holdSeconds * 1000

    readonly property string keystrokePath: {
        if (!statePath)
            return ""
        const cut = statePath.lastIndexOf("/")
        return cut < 0 ? "keys.json" : statePath.substring(0, cut + 1) + "keys.json"
    }

    width: Math.max(96, row.implicitWidth + 28)
    height: 68
    x: Screen.width / 2 - width / 2
    y: Screen.height - height - 96
    visible: keyModel.count > 0
    title: "Remcorder Keystrokes"
    color: "transparent"
    // Declared inside the indicator window, so Qt would otherwise parent it as
    // a popup of that layer surface instead of giving it its own.
    transientParent: null
    flags: Qt.FramelessWindowHint
         | Qt.WindowStaysOnTopHint
         | Qt.Tool
         | Qt.WindowTransparentForInput

    ListModel {
        id: keyModel
    }

    function syncTokens(tokens) {
        const live = {}
        for (let index = 0; index < tokens.length; index++)
            live[tokens[index].id] = true

        while (keyModel.count > 0 && !live[keyModel.get(0).tokenId])
            keyModel.remove(0)

        for (let position = 0; position < tokens.length; position++) {
            const token = tokens[position]
            if (position < keyModel.count && keyModel.get(position).tokenId === token.id) {
                if (keyModel.get(position).count !== token.count)
                    keyModel.setProperty(position, "count", token.count)
                continue
            }
            keyModel.insert(position, { tokenId: token.id, text: token.text, count: token.count })
        }

        while (keyModel.count > tokens.length)
            keyModel.remove(keyModel.count - 1)
    }

    function readKeystrokes() {
        if (!keystrokePath)
            return

        const source = keystrokePath.startsWith("/")
            ? "file://" + keystrokePath
            : keystrokePath
        const request = new XMLHttpRequest()
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE)
                return
            if (request.status !== 0 && request.status !== 200)
                return
            try {
                const snapshot = JSON.parse(request.responseText)
                if (snapshot.hold_seconds)
                    keys.holdSeconds = Number(snapshot.hold_seconds)
                const stamp = new Date(snapshot.updated_at)
                if (!isNaN(stamp.getTime()))
                    keys.updatedAt = stamp.getTime()
                keys.syncTokens(snapshot.tokens || [])
            } catch (error) {
                console.warn("Could not read keystrokes:", error)
            }
        }
        request.open("GET", source)
        request.send()
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            keys.nowMs = Date.now()
            keys.readKeystrokes()
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        opacity: keys.faded ? 0 : 1

        Behavior on opacity {
            NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: keyModel

            delegate: Rectangle {
                id: chip

                required property string text
                required property int count

                height: 40
                width: Math.max(40, glyph.implicitWidth + repeats.width + 24)
                radius: 10
                border.width: 1
                border.color: "#2C3342"

                gradient: Gradient {
                    GradientStop { position: 0; color: "#212736" }
                    GradientStop { position: 1; color: "#111621" }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        id: glyph
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.text
                        color: "#EEF1F7"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }

                    Text {
                        id: repeats
                        anchors.verticalCenter: parent.verticalCenter
                        visible: chip.count > 1
                        width: visible ? implicitWidth : 0
                        text: "×" + chip.count
                        color: "#7E8BA3"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 12
                    }
                }

                ParallelAnimation {
                    running: true
                    NumberAnimation {
                        target: chip
                        property: "scale"
                        from: 0.7
                        to: 1
                        duration: 170
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        target: chip
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 130
                    }
                }
            }
        }
    }
}
