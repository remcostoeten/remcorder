import QtQuick

DropArea {
    id: zone

    property string hint: "Drop to edit"
    property string pendingPath: ""

    signal videoDropped(string path)

    function firstVideo(urls) {
        for (let i = 0; i < urls.length; ++i) {
            const path = backend.videoPathFromUrl(urls[i])
            if (path.length > 0)
                return path
        }
        return ""
    }

    z: 1000

    onEntered: drag => {
        pendingPath = drag.hasUrls ? firstVideo(drag.urls) : ""
        drag.accepted = pendingPath.length > 0
        if (drag.accepted)
            drag.acceptProposedAction()
    }
    onExited: pendingPath = ""
    onDropped: drop => {
        const path = drop.hasUrls ? firstVideo(drop.urls) : ""
        pendingPath = ""
        if (path.length === 0)
            return
        drop.acceptProposedAction()
        zone.videoDropped(path)
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: 14
        color: "#E60A0E14"
        border.width: 2
        border.color: Theme.focusBlue
        opacity: zone.containsDrag && zone.pendingPath.length > 0 ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 120 } }

        Column {
            anchors.centerIn: parent
            width: parent.width - 40
            spacing: 10

            Glyph {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 28
                height: 28
                name: "trim"
                tint: Theme.focusInk
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: zone.hint
                color: Theme.ink
                font.family: Theme.sans
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: zone.pendingPath.split("/").pop()
                color: Theme.inkDim
                font.family: Theme.mono
                font.pixelSize: 11
                elide: Text.ElideMiddle
            }
        }
    }
}
