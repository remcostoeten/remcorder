import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

Card {
    id: card

    property string path: ""
    property bool fresh: false
    property bool renaming: false
    property string renameError: ""
    property var info: ({})

    signal trimRequested(string path)
    signal dismissed()

    function refreshInfo() {
        info = backend.recordingInfo(path)
    }

    function startRename() {
        nameField.text = info.baseName || ""
        renaming = true
        nameField.forceActiveFocus()
        nameField.selectAll()
    }

    function commitRename() {
        if (!renaming)
            return
        const wanted = nameField.text.trim()
        renaming = false
        if (wanted.length === 0 || wanted === info.baseName)
            return
        renameError = backend.renameLastRecording(wanted)
        if (renameError.length > 0)
            renameErrorTimer.restart()
    }

    function cancelRename() {
        renaming = false
    }

    function clockLabel(ms) {
        const total = Math.max(0, Math.round(ms / 1000))
        const minutes = Math.floor(total / 60)
        const seconds = total % 60
        const hours = Math.floor(minutes / 60)
        const pad = value => (value < 10 ? "0" : "") + value
        return hours > 0
            ? hours + ":" + pad(minutes % 60) + ":" + pad(seconds)
            : pad(minutes) + ":" + pad(seconds)
    }

    function timeAgo(ms) {
        if (!ms)
            return ""
        const delta = Math.max(0, Date.now() - ms)
        const minutes = Math.floor(delta / 60000)
        if (minutes < 1)
            return "just now"
        if (minutes < 60)
            return minutes + " min ago"
        const hours = Math.floor(minutes / 60)
        if (hours < 24)
            return hours + (hours === 1 ? " hour ago" : " hours ago")
        return Qt.formatDateTime(new Date(ms), "d MMM · HH:mm")
    }

    readonly property string resolutionLabel: {
        const size = thumbPlayer.metaData.value(MediaMetaData.Resolution)
        return size && size.width > 0 ? size.width + "×" + size.height : ""
    }

    readonly property string metaLine: {
        const parts = []
        if (resolutionLabel.length > 0)
            parts.push(resolutionLabel)
        if (thumbPlayer.duration > 0)
            parts.push(clockLabel(thumbPlayer.duration))
        if (info.sizeLabel)
            parts.push(info.sizeLabel)
        return parts.join("  ·  ")
    }

    implicitHeight: column.implicitHeight + 26
    color: fresh ? "#0F1511" : Theme.surface
    border.color: fresh ? Theme.tintBorder(Theme.success) : Theme.stroke

    Behavior on color { ColorAnimation { duration: 600 } }
    Behavior on border.color { ColorAnimation { duration: 600 } }

    onPathChanged: {
        renaming = false
        renameError = ""
        refreshInfo()
        thumbPlayer.stop()
        savedPreview.clear()
        thumbPlayer.source = path.length > 0 ? "file://" + encodeURI(path) : ""
        if (path.length > 0)
            thumbPlayer.play()
    }

    Timer {
        id: renameErrorTimer
        interval: 6000
        onTriggered: card.renameError = ""
    }

    Timer {
        interval: 60000
        repeat: true
        running: card.visible
        onTriggered: agoLabel.text = card.timeAgo(card.info.modifiedMs)
    }

    MediaPlayer {
        id: thumbPlayer
        videoOutput: savedPreview.videoSink
        audioOutput: AudioOutput { muted: true }
        onPositionChanged: {
            if (thumbPlayer.playbackState === MediaPlayer.PlayingState && thumbPlayer.position > 400 && savedPreview.available)
                pause()
        }
        onMediaStatusChanged: {
            if (thumbPlayer.mediaStatus === MediaPlayer.EndOfMedia)
                pause()
        }
    }

    ColumnLayout {
        id: column

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 13
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                id: thumb
                Layout.preferredWidth: 112
                Layout.preferredHeight: 63
                radius: 8
                color: "#000000"
                border.width: 1
                border.color: Theme.strokeSoft
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    source: savedPreview.available
                        ? "image://savedPreview/frame?" + savedPreview.revision
                        : ""
                    cache: false
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#000000"
                    opacity: thumbHover.hovered ? 0.35 : 0
                    Behavior on opacity { NumberAnimation { duration: 130 } }
                }

                Glyph {
                    anchors.centerIn: parent
                    name: "play"
                    width: 18
                    height: 18
                    tint: "#FFFFFF"
                    opacity: thumbHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 130 } }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    visible: thumbPlayer.duration > 0
                    width: durationText.implicitWidth + 8
                    height: 16
                    radius: 4
                    color: "#C0000000"

                    Text {
                        id: durationText
                        anchors.centerIn: parent
                        text: card.clockLabel(thumbPlayer.duration)
                        color: "#FFFFFF"
                        font.family: Theme.mono
                        font.pixelSize: 10
                    }
                }

                HoverHandler { id: thumbHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: backend.openRecentRecording(card.path) }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Glyph {
                        Layout.preferredWidth: 12
                        Layout.preferredHeight: 12
                        name: "check"
                        tint: Theme.successInk
                        weight: 2
                    }
                    Text {
                        text: card.fresh ? "Recording saved" : "Last recording"
                        color: Theme.successInk
                        font.family: Theme.sans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.3
                    }
                    Text {
                        id: agoLabel
                        text: card.timeAgo(card.info.modifiedMs)
                        color: Theme.inkFaint
                        font.family: Theme.sans
                        font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    WindowButton {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        glyph: "close"
                        tabbable: true
                        Accessible.name: "Dismiss"
                        onClicked: card.dismissed()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 7
                        color: card.renaming ? Theme.canvasLift : nameHover.hovered ? Theme.surfaceHi : "transparent"
                        border.width: 1
                        border.color: card.renaming
                            ? Theme.focusBlue
                            : nameHover.hovered ? Theme.stroke : "transparent"

                        Behavior on color { ColorAnimation { duration: 130 } }
                        Behavior on border.color { ColorAnimation { duration: 130 } }

                        HoverHandler { id: nameHover; enabled: !card.renaming }
                        TapHandler {
                            enabled: !card.renaming
                            onTapped: card.startRename()
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 4

                            Text {
                                Layout.fillWidth: true
                                visible: !card.renaming
                                text: card.info.fileName || ""
                                color: Theme.ink
                                font.family: Theme.sans
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                elide: Text.ElideMiddle
                                verticalAlignment: Text.AlignVCenter
                            }

                            TextInput {
                                id: nameField
                                Layout.fillWidth: true
                                visible: card.renaming
                                color: Theme.ink
                                font.family: Theme.sans
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                selectByMouse: true
                                selectionColor: Theme.focusBlue
                                clip: true
                                verticalAlignment: TextInput.AlignVCenter
                                Keys.onReturnPressed: card.commitRename()
                                Keys.onEnterPressed: card.commitRename()
                                Keys.onEscapePressed: card.cancelRename()
                                onActiveFocusChanged: {
                                    if (!activeFocus && card.renaming)
                                        card.commitRename()
                                }
                            }

                            Text {
                                visible: card.renaming && (card.info.suffix || "").length > 0
                                text: "." + card.info.suffix
                                color: Theme.inkFaint
                                font.family: Theme.sans
                                font.pixelSize: 13
                            }

                            Glyph {
                                Layout.preferredWidth: 13
                                Layout.preferredHeight: 13
                                visible: !card.renaming
                                name: "pencil"
                                tint: Theme.inkFaint
                                opacity: nameHover.hovered ? 1 : 0.45
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    text: card.renameError.length > 0
                        ? card.renameError
                        : card.metaLine.length > 0 ? card.metaLine : "Reading file…"
                    color: card.renameError.length > 0 ? Theme.amber : Theme.inkDim
                    font.family: card.renameError.length > 0 ? Theme.sans : Theme.mono
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            GhostButton {
                implicitHeight: 30
                glyph: "open"
                text: "Open"
                onClicked: backend.openRecentRecording(card.path)
            }
            GhostButton {
                implicitHeight: 30
                glyph: "reveal"
                text: "Show in folder"
                onClicked: backend.revealRecording(card.path)
            }
            GhostButton {
                implicitHeight: 30
                glyph: "trim"
                text: "Trim"
                enabled: !backend.processingTrim
                onClicked: card.trimRequested(card.path)
            }

            Item { Layout.fillWidth: true }

            GhostButton {
                implicitHeight: 30
                implicitWidth: 34
                glyph: "pencil"
                fill: "transparent"
                bordered: false
                textColor: Theme.inkDim
                Accessible.name: "Rename recording"
                onClicked: card.startRename()
            }
            GhostButton {
                implicitHeight: 30
                implicitWidth: 34
                glyph: "copy"
                fill: "transparent"
                bordered: false
                textColor: Theme.inkDim
                Accessible.name: "Copy path"
                onClicked: backend.copyLastOutputPath()
            }
        }
    }
}
