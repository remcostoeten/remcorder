import QtQuick

Item {
    id: strip

    implicitWidth: row.implicitWidth
    opacity: backend.keystrokesVisible ? 1 : 0

    Behavior on opacity {
        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
    }

    ListModel {
        id: keyModel
    }

    function sync(tokens) {
        const live = {}
        for (let index = 0; index < tokens.length; index++)
            live[tokens[index].tokenId] = true

        while (keyModel.count > 0 && !live[keyModel.get(0).tokenId])
            keyModel.remove(0)

        for (let position = 0; position < tokens.length; position++) {
            const token = tokens[position]
            if (position < keyModel.count && keyModel.get(position).tokenId === token.tokenId) {
                if (keyModel.get(position).count !== token.count)
                    keyModel.setProperty(position, "count", token.count)
                continue
            }
            keyModel.insert(position, { tokenId: token.tokenId, text: token.text, count: token.count })
        }

        while (keyModel.count > tokens.length)
            keyModel.remove(keyModel.count - 1)
    }

    Connections {
        target: backend
        function onKeystrokesChanged() {
            strip.sync(backend.keystrokeTokens)
        }
    }

    Row {
        id: row
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
            model: keyModel

            delegate: Rectangle {
                id: chip

                required property string text
                required property int count

                height: 36
                width: Math.max(36, glyph.implicitWidth + (repeats.visible ? repeats.implicitWidth + 4 : 0) + 22)
                radius: 9
                color: "#F2101013"
                border.width: 1
                border.color: Theme.strokeHi

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.topMargin: 1
                    height: 1
                    color: "#1AFFFFFF"
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        id: glyph
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.text
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }

                    Text {
                        id: repeats
                        anchors.verticalCenter: parent.verticalCenter
                        visible: chip.count > 1
                        text: "\u00d7" + chip.count
                        color: Theme.inkDim
                        font.family: Theme.mono
                        font.pixelSize: 11
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
