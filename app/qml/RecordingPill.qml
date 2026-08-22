import QtQuick
import QtQuick.Window

Window {
    id: pill

    readonly property bool counting: backend.countingDown
    readonly property color accent: backend.processingTrim
        ? Theme.success
        : counting
        ? Theme.focusBlue
        : backend.paused ? Theme.amber : Theme.signal

    function place() {
        const target = Qt.application.screens.length > 0 ? Qt.application.screens[0] : null
        if (!target)
            return
        x = target.virtualX + Math.round((target.width - width) / 2)
        y = target.virtualY + target.height - height - 64
    }

    width: shell.implicitWidth
    height: 46
    visible: false
    color: "transparent"
    title: "Remcorder"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool

    onVisibleChanged: {
        if (visible)
            place()
    }

    Rectangle {
        id: shell

        implicitWidth: content.implicitWidth + 28
        anchors.fill: parent
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
                onActivated: backend.togglePause()
            }

            PillButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: !pill.counting
                glyph: "stop"
                hint: "Stop and save"
                accent: Theme.signal
                onActivated: backend.stopRecording()
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
