import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia

Window {
    id: trimWindow

    property string sourcePath: ""
    property bool rangeInitialized: false
    property bool awaitingPreviewFrame: false
    property bool motionBlur: false
    property string motionBlurStrength: "smooth"

    function openForSource(path) {
        sourcePath = path
        rangeInitialized = false
        awaitingPreviewFrame = true
        motionBlur = false
        trimPreview.clear()
        show()
        raise()
        requestActivate()
        trimPlayer.source = "file://" + encodeURI(path)
        trimPlayer.play()
    }

    function dismiss() {
        awaitingPreviewFrame = false
        trimPlayer.stop()
        hide()
    }

    function baseName(path) {
        const parts = String(path).split("/")
        return parts[parts.length - 1]
    }

    width: 660
    height: 720
    minimumWidth: 540
    minimumHeight: 620
    visible: false
    title: "Trim · Remcorder"
    color: Theme.canvas
    flags: Qt.Window | Qt.FramelessWindowHint

    readonly property real inMs: trimRange.first.value * 1000
    readonly property real outMs: trimRange.second.value * 1000

    function seekTo(ms) {
        trimPlayer.position = Math.max(0, Math.min(trimPlayer.duration, Math.round(ms)))
    }

    function playSelection() {
        if (trimPlayer.position < inMs || trimPlayer.position >= outMs)
            seekTo(inMs)
        trimPlayer.play()
    }

    MediaPlayer {
        id: trimPlayer
        videoOutput: trimPreview.videoSink
        audioOutput: AudioOutput { muted: true }
        onPositionChanged: {
            if (trimWindow.awaitingPreviewFrame || !trimWindow.rangeInitialized)
                return
            if (playbackState === MediaPlayer.PlayingState && position >= trimWindow.outMs)
                trimWindow.seekTo(trimWindow.inMs)
        }
        onDurationChanged: function() {
            if (duration > 0 && !trimWindow.rangeInitialized) {
                const seconds = duration / 1000
                Qt.callLater(() => {
                    trimRange.first.value = 0
                    trimRange.second.value = seconds
                    trimWindow.rangeInitialized = true
                })
            }
        }
    }

    Connections {
        target: trimPreview

        function onFrameChanged() {
            if (!trimWindow.awaitingPreviewFrame || !trimPreview.available)
                return

            trimWindow.awaitingPreviewFrame = false
            trimPlayer.pause()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Theme.stroke
        z: 100
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: Theme.canvas

            DragHandler {
                target: null
                onActiveChanged: {
                    if (active)
                        windowChrome.startMove(trimWindow)
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 12
                spacing: 10

                Glyph {
                    Layout.preferredWidth: 15
                    Layout.preferredHeight: 15
                    name: "trim"
                    tint: Theme.inkDim
                }

                Text {
                    text: "Trim a copy"
                    color: Theme.ink
                    font.family: Theme.sans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    text: trimWindow.baseName(trimWindow.sourcePath)
                    color: Theme.inkFaint
                    font.family: Theme.mono
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }

                WindowButton {
                    glyph: "close"
                    hoverFill: Theme.signal
                    hoverInk: "#FFFFFF"
                    Accessible.name: "Close trim editor"
                    onClicked: trimWindow.dismiss()
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.strokeSoft
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 20
            spacing: 14

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 160
                radius: 12
                color: "#000000"
                border.width: 1
                border.color: Theme.strokeSoft
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    source: trimPreview.available
                        ? "image://trimPreview/frame?" + trimPreview.revision
                        : ""
                    cache: false
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    anchors.centerIn: parent
                    visible: !trimPreview.available
                    text: "Loading preview…"
                    color: Theme.inkFaint
                    font.family: Theme.sans
                    font.pixelSize: 12
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                GhostButton {
                    implicitWidth: 96
                    implicitHeight: 36
                    glyph: trimPlayer.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
                    text: trimPlayer.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"
                    onClicked: {
                        if (trimPlayer.playbackState === MediaPlayer.PlayingState)
                            trimPlayer.pause()
                        else
                            trimWindow.playSelection()
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: backend.formatDuration(Math.floor(trimPlayer.position / 1000))
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 13
                }
            }

            Item {
                id: scrubBar

                Layout.fillWidth: true
                Layout.preferredHeight: 14
                Layout.bottomMargin: -6
                z: 1

                readonly property real trackX: trimRange.leftPadding
                readonly property real trackWidth: trimRange.availableWidth
                readonly property real fraction: trimPlayer.duration > 0
                    ? trimPlayer.position / trimPlayer.duration
                    : 0

                function seekAt(localX) {
                    if (trimPlayer.duration <= 0)
                        return
                    const ratio = Math.max(0, Math.min(1, (localX - trackX) / trackWidth))
                    trimWindow.seekTo(ratio * trimPlayer.duration)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => scrubBar.seekAt(mouse.x)
                    onPositionChanged: mouse => {
                        if (pressed)
                            scrubBar.seekAt(mouse.x)
                    }
                }

                Item {
                    id: playhead

                    x: scrubBar.trackX + scrubBar.fraction * scrubBar.trackWidth - width / 2
                    y: 0
                    width: 8
                    height: scrubBar.height + 22
                    visible: trimPlayer.duration > 0

                    Rectangle {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 8
                        height: 8
                        radius: 2
                        color: Theme.ink
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 2
                        color: Theme.ink
                    }
                }
            }

            RangeSlider {
                id: trimRange
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                from: 0
                to: Math.max(0.25, trimPlayer.duration / 1000)
                stepSize: 0.1
                first.onMoved: trimWindow.seekTo(first.value * 1000)
                second.onMoved: trimWindow.seekTo(second.value * 1000)

                background: Item {
                    x: trimRange.leftPadding
                    y: (trimRange.height - height) / 2
                    width: trimRange.availableWidth
                    height: 18

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 5
                        radius: 2.5
                        color: "#1D1D22"
                    }
                    Rectangle {
                        x: trimRange.first.visualPosition * parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0,
                            (trimRange.second.visualPosition
                             - trimRange.first.visualPosition) * parent.width)
                        height: 5
                        radius: 2.5
                        color: Theme.focusBlue
                    }
                }
                first.handle: Rectangle {
                    x: trimRange.leftPadding
                        + trimRange.first.visualPosition
                        * (trimRange.availableWidth - width)
                    y: (trimRange.height - height) / 2
                    width: 16
                    height: 16
                    radius: 8
                    color: activeFocus ? Theme.focusInk : "#FFFFFF"
                    border.width: 4
                    border.color: Theme.focusBlue
                    scale: trimRange.first.pressed || activeFocus ? 1.15 : 1

                    Behavior on scale { NumberAnimation { duration: 110 } }
                }
                second.handle: Rectangle {
                    x: trimRange.leftPadding
                        + trimRange.second.visualPosition
                        * (trimRange.availableWidth - width)
                    y: (trimRange.height - height) / 2
                    width: 16
                    height: 16
                    radius: 8
                    color: activeFocus ? Theme.focusInk : "#FFFFFF"
                    border.width: 4
                    border.color: Theme.focusBlue
                    scale: trimRange.second.pressed || activeFocus ? 1.15 : 1

                    Behavior on scale { NumberAnimation { duration: 110 } }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "IN " + backend.formatDuration(Math.floor(trimRange.first.value))
                    color: Theme.inkFaint
                    font.family: Theme.mono
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: backend.formatDuration(
                        Math.max(0, Math.floor(trimRange.second.value - trimRange.first.value)))
                        + " selected"
                    color: Theme.ink
                    font.family: Theme.mono
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "OUT " + backend.formatDuration(Math.floor(trimRange.second.value))
                    color: Theme.inkFaint
                    font.family: Theme.mono
                    font.pixelSize: 11
                }
            }

            Card {
                Layout.fillWidth: true
                implicitHeight: blurColumn.implicitHeight + 24
                border.color: trimWindow.motionBlur ? "#233752" : Theme.stroke

                Behavior on border.color { ColorAnimation { duration: 180 } }

                ColumnLayout {
                    id: blurColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                spacing: 8

                                Text {
                                    text: "Motion blur"
                                    color: Theme.ink
                                    font.family: Theme.sans
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                Rectangle {
                                    Layout.preferredHeight: 17
                                    Layout.preferredWidth: betaLabel.implicitWidth + 13
                                    radius: 5
                                    color: "#0E1620"
                                    border.width: 1
                                    border.color: "#233752"

                                    Text {
                                        id: betaLabel
                                        anchors.centerIn: parent
                                        text: "BETA"
                                        color: Theme.focusInk
                                        font.family: Theme.sans
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.8
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Blend frames together as the copy is exported."
                                color: Theme.inkDim
                                font.family: Theme.sans
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }

                        ModernSwitch {
                            checked: trimWindow.motionBlur
                            onToggled: trimWindow.motionBlur = checked
                            Accessible.name: "Apply motion blur to the exported copy"
                        }
                    }

                    Segmented {
                        visible: trimWindow.motionBlur
                        Layout.fillWidth: true
                        implicitHeight: 36
                        options: [
                            { value: "subtle", label: "Subtle" },
                            { value: "smooth", label: "Smooth" },
                            { value: "strong", label: "Strong" }
                        ]
                        current: trimWindow.motionBlurStrength
                        onPicked: value => trimWindow.motionBlurStrength = value
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                GhostButton {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    text: "Cancel"
                    onClicked: trimWindow.dismiss()
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    tint: Theme.focusBlue
                    enabled: trimWindow.rangeInitialized
                        && trimRange.second.value - trimRange.first.value >= 0.25
                    text: trimWindow.motionBlur ? "Export blurred copy" : "Export trimmed copy"
                    onClicked: {
                        trimPlayer.pause()
                        backend.exportTrim(
                            trimWindow.sourcePath,
                            trimRange.first.value,
                            trimRange.second.value,
                            trimWindow.motionBlur,
                            trimWindow.motionBlurStrength)
                        trimWindow.dismiss()
                    }
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        z: 200

        component Grip: MouseArea {
            property int edges: 0
            acceptedButtons: Qt.LeftButton
            onPressed: windowChrome.startResize(trimWindow, edges)
        }

        Grip {
            edges: Qt.BottomEdge | Qt.RightEdge
            cursorShape: Qt.SizeFDiagCursor
            width: 16
            height: 16
            anchors { bottom: parent.bottom; right: parent.right }
        }
        Grip {
            edges: Qt.RightEdge
            cursorShape: Qt.SizeHorCursor
            width: 5
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; bottomMargin: 16 }
        }
        Grip {
            edges: Qt.BottomEdge
            cursorShape: Qt.SizeVerCursor
            height: 5
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; rightMargin: 16 }
        }
        Grip {
            edges: Qt.LeftEdge
            cursorShape: Qt.SizeHorCursor
            width: 5
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        }
        Grip {
            edges: Qt.TopEdge
            cursorShape: Qt.SizeVerCursor
            height: 5
            anchors { top: parent.top; left: parent.left; right: parent.right }
        }
    }
}
