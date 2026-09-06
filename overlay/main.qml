import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell

// Wayland compositors ignore WindowStaysOnTopHint, so the indicator is a
// layer-shell overlay surface: always above other windows, placed by the
// compositor from anchors and margins rather than x/y. On X11 the attached
// properties are inert and the window flags below do the job.
Window {
    id: root

    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.margins.top: 60
    LayerShell.Window.margins.right: 40
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.scope: "remcorder-overlay"

    property bool recording: false
    property bool paused: false
    property int snapshotDuration: 0
    property date observedAt: new Date()
    property string elapsed: "00:00"
    property string statePath: {
        const args = Qt.application.arguments
        return args.length > 1 ? args[args.length - 1] : ""
    }

    width: 202
    height: 54
    visible: recording
    title: "Remcorder Overlay"
    color: "transparent"
    flags: Qt.FramelessWindowHint
         | Qt.WindowStaysOnTopHint
         | Qt.Tool
         | Qt.WindowTransparentForInput

    function formatElapsed() {
        const sinceSnapshot = paused
            ? 0
            : Math.max(0, Math.floor((Date.now() - observedAt.getTime()) / 1000))
        const total = Math.max(0, snapshotDuration + sinceSnapshot)
        const hours = Math.floor(total / 3600)
        const minutes = Math.floor((total % 3600) / 60)
        const seconds = total % 60
        const pair = value => String(value).padStart(2, "0")
        elapsed = hours > 0
            ? pair(hours) + ":" + pair(minutes) + ":" + pair(seconds)
            : pair(minutes) + ":" + pair(seconds)
    }

    function readState() {
        if (!statePath)
            return

        const source = statePath.startsWith("/")
            ? "file://" + statePath
            : statePath
        const request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE)
                return
            if (request.status !== 0 && request.status !== 200)
                return
            try {
                const state = JSON.parse(request.responseText)
                const wasRecording = recording
                recording = Boolean(state.recording)
                paused = Boolean(state.paused)
                snapshotDuration = Number(state.duration_seconds) || 0
                if (recording && state.observed_at) {
                    const parsed = new Date(state.observed_at)
                    if (!isNaN(parsed.getTime()))
                        observedAt = parsed
                    formatElapsed()
                }
                if (!wasRecording && recording)
                    entrance.restart()
            } catch (error) {
                console.warn("Could not read recorder state:", error)
            }
        }
        request.open("GET", source)
        request.send()
    }

    Component.onCompleted: readState()

    KeystrokeOverlay {
        statePath: root.statePath
    }

    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            root.readState()
            if (root.recording)
                root.formatElapsed()
        }
    }

    ParallelAnimation {
        id: entrance
        NumberAnimation {
            target: capsule
            property: "scale"
            from: 0.92
            to: 1
            duration: 220
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: capsule
            property: "opacity"
            from: 0
            to: 1
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: capsule
        anchors.fill: parent
        anchors.margins: 3
        radius: 24
        border.width: 1
        border.color: "#2C3342"

        gradient: Gradient {
            GradientStop { position: 0; color: "#1A1F2B" }
            GradientStop { position: 1; color: "#0E121A" }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            height: 1
            color: "#1FFFFFFF"
        }

        Row {
            anchors.centerIn: parent
            spacing: 12

            Item {
                width: 26
                height: 26

                Rectangle {
                    id: pulse
                    visible: !root.paused
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    radius: 11
                    color: "transparent"
                    border.width: 1
                    border.color: root.paused ? "#FFC16A" : "#FF5C6C"
                    opacity: 0

                    SequentialAnimation on scale {
                        running: root.recording && !root.paused
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0.55
                            to: 1.25
                            duration: 1100
                            easing.type: Easing.OutCubic
                        }
                        PauseAnimation { duration: 350 }
                    }
                    SequentialAnimation on opacity {
                        running: root.recording && !root.paused
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.8; to: 0; duration: 1100 }
                        PauseAnimation { duration: 350 }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    radius: root.paused ? 2 : 5
                    color: root.paused ? "#FFC16A" : "#FF4054"

                    Behavior on radius {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 140 }
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: root.paused ? "PAUSED" : "CAPTURING"
                    color: root.paused ? "#FFB86B" : "#98A3B5"
                    font.family: "Inter"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.7
                }

                Text {
                    text: root.elapsed
                    color: "#EEF1F7"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    font.letterSpacing: 0.8
                }
            }
        }
    }
}
