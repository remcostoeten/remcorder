import QtQuick
import QtQuick.Controls
import QtQuick.Window

Window {
    id: pill

    readonly property bool counting: backend.countingDown
    readonly property color accent: backend.processingTrim
        ? Theme.success
        : counting
        ? Theme.focusBlue
        : backend.paused ? Theme.amber : Theme.signal

    readonly property int bottomOffset: 64
    property bool pinned: false
    property bool confirmingDiscard: false

    Timer {
        id: discardTimer
        interval: 2500
        onTriggered: pill.confirmingDiscard = false
    }

    function armDiscard() {
        if (confirmingDiscard) {
            confirmingDiscard = false
            discardTimer.stop()
            backend.discardRecording()
            return
        }
        confirmingDiscard = true
        discardTimer.restart()
    }

    function disarmDiscard() {
        confirmingDiscard = false
        discardTimer.stop()
    }

    function place() {
        if (pinned) {
            const output = screen ?? (Qt.application.screens.length > 0 ? Qt.application.screens[0] : null)
            if (!output)
                return
            windowChrome.moveOverlay(pill, Math.round((output.width - width) / 2), 0, 0, bottomOffset)
            return
        }
        const target = Qt.application.screens.length > 0 ? Qt.application.screens[0] : null
        if (!target)
            return
        x = target.virtualX + Math.round((target.width - width) / 2)
        y = target.virtualY + target.height - height - bottomOffset
    }

    Component.onCompleted: {
        pinned = windowChrome.pinAbove(pill, WindowChrome.AnchorBottom | WindowChrome.AnchorLeft, 0, 0, 0, bottomOffset)
    }

    readonly property int capsuleHeight: 46
    readonly property bool stripAttached: backend.showKeystrokes && backend.keystrokePlacement === "pill"
    readonly property int stripHeight: stripAttached ? 56 : 0

    width: Math.max(shell.implicitWidth, stripAttached && backend.keystrokesVisible ? strip.implicitWidth : 0)
    height: capsuleHeight + stripHeight
    visible: false
    color: "transparent"
    title: "Remcorder Recording"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool

    onVisibleChanged: {
        disarmDiscard()
        if (visible) {
            place()
            syncInputRect()
        }
    }

    // The mask doubles as the X11 window shape, so the strip must be inside it
    // whenever it has anything to paint, including while it fades out.
    readonly property bool stripPainted: stripAttached && strip.opacity > 0

    function syncInputRect() {
        const rects = [Qt.rect(0, pill.stripHeight, shell.width, pill.capsuleHeight)]
        if (stripPainted)
            rects.push(Qt.rect(0, 0, Math.max(strip.implicitWidth, 1), pill.stripHeight))
        windowChrome.setInputRects(pill, rects)
    }

    onStripHeightChanged: syncInputRect()
    onStripPaintedChanged: syncInputRect()
    onWidthChanged: syncInputRect()

    KeystrokeStrip {
        id: strip
        anchors.left: parent.left
        anchors.top: parent.top
        height: pill.stripHeight
        visible: pill.stripHeight > 0
        onImplicitWidthChanged: pill.syncInputRect()
    }

    Rectangle {
        id: shell

        implicitWidth: content.implicitWidth + 28
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: implicitWidth
        height: pill.capsuleHeight
        radius: height / 2
        color: "#F2101013"
        border.width: 1
        border.color: Qt.rgba(pill.accent.r, pill.accent.g, pill.accent.b, 0.45)

        Behavior on border.color { ColorAnimation { duration: 220 } }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 1
            height: 1
            color: "#1AFFFFFF"
        }

        DragHandler {
            target: null
            onActiveChanged: {
                if (active)
                    windowChrome.startMove(pill)
            }
        }

        Row {
            id: content

            anchors.centerIn: parent
            spacing: 10

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20

                Rectangle {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    radius: 10
                    color: "transparent"
                    border.width: 1.4
                    border.color: pill.accent
                    opacity: 0

                    SequentialAnimation on scale {
                        running: pill.visible && backend.recording && !backend.paused
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.7; to: 1.9; duration: 1400; easing.type: Easing.OutCubic }
                    }
                    SequentialAnimation on opacity {
                        running: pill.visible && backend.recording && !backend.paused
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.6; to: 0; duration: 1400 }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: backend.paused ? 12 : 11
                    height: width
                    radius: backend.paused ? 3 : width / 2
                    color: pill.accent
                    visible: !pill.counting

                    Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 220 } }
                }

                Text {
                    anchors.centerIn: parent
                    visible: pill.counting
                    text: backend.countdownRemaining
                    color: pill.accent
                    font.family: Theme.mono
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.counting
                    ? "Starting…"
                    : backend.formatDuration(backend.durationSeconds)
                color: Theme.ink
                font.family: pill.counting ? Theme.sans : Theme.mono
                font.pixelSize: pill.counting ? 13 : 15
                font.weight: Font.Medium
                font.letterSpacing: pill.counting ? 0 : 0.8
            }

            Row {
                id: statusDots

                readonly property var entries: [
                    { on: backend.microphoneEnabled, tint: Theme.successInk, name: "Microphone on" },
                    { on: backend.webcamEnabled, tint: Theme.successInk, name: "Webcam bubble on" },
                    { on: backend.showKeystrokes, tint: Theme.focusInk, name: "Keystrokes shown" }
                ]
                readonly property bool any: entries.some(entry => entry.on)

                anchors.verticalCenter: parent.verticalCenter
                visible: !pill.counting && any
                spacing: 4

                Repeater {
                    model: statusDots.entries

                    delegate: Rectangle {
                        required property var modelData

                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.on
                        width: 5
                        height: 5
                        radius: 2.5
                        color: modelData.tint
                        opacity: 0.85

                        ToolTip.visible: dotHover.hovered
                        ToolTip.text: modelData.name
                        ToolTip.delay: 400

                        HoverHandler { id: dotHover }
                    }
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 20
                color: Theme.stroke
            }

            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: !pill.counting
                glyph: backend.paused ? "play" : "pause"
                hint: backend.paused ? "Resume" : "Pause"
                onActivated: {
                    pill.disarmDiscard()
                    backend.togglePause()
                }
            }

            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: !pill.counting
                glyph: "stop"
                hint: "Stop and save"
                accent: Theme.signal
                onActivated: {
                    pill.disarmDiscard()
                    backend.stopRecording()
                }
            }

            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: !pill.counting
                glyph: "trash"
                hint: pill.confirmingDiscard ? "Click again to discard" : "Stop without saving"
                label: pill.confirmingDiscard ? "Discard?" : ""
                accent: pill.confirmingDiscard ? Theme.signal : Theme.ink
                active: pill.confirmingDiscard
                onActivated: pill.armDiscard()
            }

            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: !pill.counting
                glyph: "keys"
                hint: backend.showKeystrokes ? "Hide keystrokes" : "Show keystrokes"
                accent: Theme.focusInk
                active: backend.showKeystrokes
                onActivated: backend.showKeystrokes = !backend.showKeystrokes
            }

            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.counting
                glyph: "close"
                hint: "Cancel"
                accent: Theme.signal
                onActivated: backend.cancelCountdown()
            }
        }
    }
}
