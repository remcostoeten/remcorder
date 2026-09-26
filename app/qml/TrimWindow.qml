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
    property string loadError: ""
    property real exportVolume: 1.0
    property bool muteAudio: false
    property bool previewAudible: false
    property var waveformPeaks: []
    property bool waveformLoading: false
    readonly property bool hasAudio: waveformPeaks.length > 0
    property string blurPreviewState: "idle"
    property string blurPreviewMode: "split"
    property string blurPreviewBlurred: ""
    property string blurPreviewSplit: ""
    property string blurPreviewError: ""
    readonly property bool blurPreviewShowing: blurPreviewState === "ready"

    function openForSource(path) {
        sourcePath = path
        loadError = ""
        exportVolume = 1.0
        muteAudio = false
        previewAudible = false
        waveformPeaks = []
        waveformLoading = true
        backend.loadWaveform(path)
        closeBlurPreview()
        rangeInitialized = false
        awaitingPreviewFrame = true
        motionBlur = false
        trimPreview.clear()
        show()
        raise()
        requestActivate()
        trimPlayer.source = backend.fileUrl(path)
        trimPlayer.play()
    }

    function dismiss() {
        awaitingPreviewFrame = false
        backend.cancelWaveform()
        closeBlurPreview()
        trimPlayer.stop()
        hide()
    }

    function blurPreviewStart() {
        const latest = Math.max(trimRange.first.value, trimRange.second.value - 2)
        return Math.min(Math.max(trimPlayer.position / 1000, trimRange.first.value), latest)
    }

    function renderBlurPreview() {
        trimPlayer.pause()
        blurPlayer.stop()
        blurPreviewError = ""
        blurPreviewState = "rendering"
        backend.renderBlurPreview(sourcePath, blurPreviewStart(), motionBlurStrength)
    }

    function closeBlurPreview() {
        backend.cancelBlurPreview()
        blurPlayer.stop()
        blurPlayer.source = ""
        blurPreview.clear()
        blurPreviewState = "idle"
        blurPreviewError = ""
    }

    function showBlurPreview() {
        blurPlayer.source = backend.fileUrl(
            blurPreviewMode === "split" ? blurPreviewSplit : blurPreviewBlurred)
        blurPlayer.play()
    }

    onMotionBlurStrengthChanged: {
        if (blurPreviewState !== "idle")
            renderBlurPreview()
    }
    onMotionBlurChanged: {
        if (!motionBlur)
            closeBlurPreview()
    }
    onBlurPreviewModeChanged: {
        if (blurPreviewShowing)
            showBlurPreview()
    }

    function chooseAnotherSource() {
        const path = backend.chooseVideoToTrim()
        if (path.length > 0)
            openForSource(path)
    }

    function baseName(path) {
        const parts = String(path).split("/")
        return parts[parts.length - 1]
    }

    width: 660
    height: 840
    minimumWidth: 540
    minimumHeight: 740
    visible: false
    title: "Edit video · Remcorder"
    color: Theme.canvas
    flags: Qt.Window | Qt.FramelessWindowHint

    readonly property real inMs: trimRange.first.value * 1000
    readonly property real outMs: trimRange.second.value * 1000

    function seekTo(ms) {
        trimPlayer.position = Math.max(0, Math.min(trimPlayer.duration, Math.round(ms)))
    }

    function playSelection() {
        if (blurPreviewState !== "idle")
            closeBlurPreview()
        if (trimPlayer.position < inMs || trimPlayer.position >= outMs)
            seekTo(inMs)
        previewAudible = true
        trimPlayer.play()
    }

    MediaPlayer {
        id: trimPlayer
        videoOutput: trimPreview.videoSink
        audioOutput: AudioOutput {
            muted: !trimWindow.previewAudible || trimWindow.muteAudio
            volume: trimWindow.exportVolume
        }
        onErrorOccurred: (error, errorString) => {
            trimWindow.awaitingPreviewFrame = false
            trimWindow.loadError = errorString.length > 0
                ? errorString
                : "This file could not be played."
        }
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

    MediaPlayer {
        id: blurPlayer
        videoOutput: blurPreview.videoSink
        loops: MediaPlayer.Infinite
    }

    Connections {
        target: backend

        function onBlurPreviewReady(blurredPath, splitPath) {
            if (trimWindow.blurPreviewState !== "rendering")
                return
            trimWindow.blurPreviewBlurred = blurredPath
            trimWindow.blurPreviewSplit = splitPath
            trimWindow.blurPreviewState = "ready"
            trimWindow.showBlurPreview()
        }

        function onBlurPreviewFailed(message) {
            if (trimWindow.blurPreviewState !== "rendering")
                return
            trimWindow.blurPreviewError = message
            trimWindow.blurPreviewState = "failed"
        }

        function onWaveformReady(path, peaks) {
            if (path !== trimWindow.sourcePath)
                return
            trimWindow.waveformPeaks = peaks
            trimWindow.waveformLoading = false
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
                    text: "Edit a copy"
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

                GhostButton {
                    implicitHeight: 30
                    fill: "transparent"
                    bordered: false
                    glyph: "folder"
                    text: "Open…"
                    textColor: Theme.inkDim
                    Accessible.name: "Open a different video"
                    onClicked: trimWindow.chooseAnotherSource()
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

                Image {
                    id: blurFrame
                    anchors.fill: parent
                    anchors.margins: 1
                    visible: trimWindow.blurPreviewShowing
                    source: visible && blurPreview.available
                        ? "image://blurPreview/frame?" + blurPreview.revision
                        : ""
                    cache: false
                    fillMode: Image.PreserveAspectFit

                    Rectangle {
                        anchors.fill: parent
                        color: "#000000"
                        z: -1
                    }
                }

                Row {
                    x: blurFrame.x + (blurFrame.width - width) / 2
                    y: blurFrame.y + (blurFrame.height - blurFrame.paintedHeight) / 2 + 10
                    width: blurFrame.paintedWidth
                    visible: trimWindow.blurPreviewShowing

                    Repeater {
                        model: trimWindow.blurPreviewMode === "split"
                            ? ["Original", "Motion blur"]
                            : ["Motion blur preview"]

                        Item {
                            id: previewTag
                            required property string modelData
                            width: trimWindow.blurPreviewMode === "split" ? parent.width / 2 : parent.width
                            height: 22

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: previewLabel.implicitWidth + 16
                                height: parent.height
                                radius: 6
                                color: "#CC0A0A0C"

                                Text {
                                    id: previewLabel
                                    anchors.centerIn: parent
                                    text: previewTag.modelData
                                    color: Theme.ink
                                    font.family: Theme.sans
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 11
                    visible: trimWindow.blurPreviewState === "rendering"
                    color: "#B0000000"

                    Text {
                        anchors.centerIn: parent
                        text: "Rendering a 2 second blur preview…"
                        color: Theme.ink
                        font.family: Theme.sans
                        font.pixelSize: 12
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: !trimPreview.available || trimWindow.loadError.length > 0
                    text: trimWindow.loadError.length > 0
                        ? "Can't preview this file: " + trimWindow.loadError
                        : "Loading preview…"
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
                id: waveform

                Layout.fillWidth: true
                Layout.preferredHeight: 56

                readonly property real gain: trimWindow.muteAudio ? 0 : trimWindow.exportVolume

                Rectangle {
                    x: scrubBar.trackX
                    width: scrubBar.trackWidth
                    height: parent.height
                    radius: 8
                    color: "#0C0C0F"
                    border.width: 1
                    border.color: Theme.strokeSoft
                }

                Canvas {
                    id: waveCanvas

                    x: scrubBar.trackX + 4
                    y: 4
                    width: scrubBar.trackWidth - 8
                    height: parent.height - 8

                    readonly property real selectionStart: trimRange.first.position
                    readonly property real selectionEnd: trimRange.second.position

                    onSelectionStartChanged: requestPaint()
                    onSelectionEndChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    Connections {
                        target: trimWindow
                        function onWaveformPeaksChanged() { waveCanvas.requestPaint() }
                    }
                    Connections {
                        target: waveform
                        function onGainChanged() { waveCanvas.requestPaint() }
                    }

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const peaks = trimWindow.waveformPeaks
                        if (peaks.length === 0)
                            return
                        const step = width / peaks.length
                        const barWidth = Math.max(1, step - (step > 3 ? 1 : 0))
                        const middle = height / 2
                        for (let i = 0; i < peaks.length; ++i) {
                            const position = (i + 0.5) / peaks.length
                            const inside = position >= selectionStart && position <= selectionEnd
                            const half = Math.max(0.75, peaks[i] * waveform.gain * middle)
                            ctx.fillStyle = inside ? Theme.focusBlue : "#34343C"
                            ctx.fillRect(i * step, middle - half, barWidth, half * 2)
                        }
                    }
                }

                Rectangle {
                    x: scrubBar.trackX + scrubBar.fraction * scrubBar.trackWidth - 1
                    width: 2
                    height: parent.height
                    color: Theme.ink
                    visible: trimPlayer.duration > 0 && trimWindow.hasAudio
                }

                Text {
                    anchors.centerIn: parent
                    visible: !trimWindow.hasAudio
                    text: trimWindow.waveformLoading ? "Reading audio…" : "No audio track"
                    color: Theme.inkFaint
                    font.family: Theme.sans
                    font.pixelSize: 11
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
                                text: "Blends neighbouring frames so scrolling and window drags look "
                                    + "smoother. Very fast motion shows as ghost copies; still content stays sharp."
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

                    RowLayout {
                        visible: trimWindow.motionBlur
                        Layout.fillWidth: true
                        spacing: 8

                        GhostButton {
                            implicitHeight: 32
                            glyph: trimWindow.blurPreviewShowing ? "close" : "play"
                            text: trimWindow.blurPreviewShowing
                                ? "Close preview"
                                : trimWindow.blurPreviewState === "rendering"
                                ? "Rendering…"
                                : "Preview at playhead"
                            enabled: trimWindow.rangeInitialized
                                && trimWindow.loadError.length === 0
                                && trimWindow.blurPreviewState !== "rendering"
                            Accessible.name: "Preview motion blur for two seconds from the playhead"
                            onClicked: {
                                if (trimWindow.blurPreviewShowing)
                                    trimWindow.closeBlurPreview()
                                else
                                    trimWindow.renderBlurPreview()
                            }
                        }

                        Segmented {
                            visible: trimWindow.blurPreviewShowing
                            Layout.fillWidth: true
                            implicitHeight: 32
                            options: [
                                { value: "split", label: "Split" },
                                { value: "blurred", label: "Blurred" }
                            ]
                            current: trimWindow.blurPreviewMode
                            onPicked: value => trimWindow.blurPreviewMode = value
                        }

                        Text {
                            visible: trimWindow.blurPreviewState === "failed"
                            Layout.fillWidth: true
                            text: "Preview failed: " + trimWindow.blurPreviewError
                            color: Theme.signal
                            font.family: Theme.sans
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Card {
                Layout.fillWidth: true
                implicitHeight: audioColumn.implicitHeight + 24
                enabled: trimWindow.hasAudio
                opacity: enabled ? 1 : 0.45

                ColumnLayout {
                    id: audioColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Audio"
                                color: Theme.ink
                                font.family: Theme.sans
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            Text {
                                Layout.fillWidth: true
                                text: trimWindow.muteAudio
                                    ? "The copy is exported without sound."
                                    : "Lower the volume of the exported copy."
                                color: Theme.inkDim
                                font.family: Theme.sans
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            text: "Mute"
                            color: Theme.inkDim
                            font.family: Theme.sans
                            font.pixelSize: 12
                        }
                        ModernSwitch {
                            checked: trimWindow.muteAudio
                            onToggled: trimWindow.muteAudio = checked
                            Accessible.name: "Remove audio from the exported copy"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: !trimWindow.muteAudio
                        spacing: 9

                        Glyph {
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                            name: "speaker"
                            tint: Theme.inkDim
                        }

                        Slider {
                            id: volumeSlider
                            Layout.fillWidth: true
                            from: 0
                            to: 1
                            stepSize: 0.01
                            value: trimWindow.exportVolume
                            onMoved: trimWindow.exportVolume = value
                            Accessible.name: "Export volume"

                            background: Rectangle {
                                x: volumeSlider.leftPadding
                                y: volumeSlider.topPadding + (volumeSlider.availableHeight - height) / 2
                                width: volumeSlider.availableWidth
                                height: 5
                                radius: 2.5
                                color: "#1D1D22"

                                Rectangle {
                                    width: volumeSlider.visualPosition * parent.width
                                    height: parent.height
                                    radius: 2.5
                                    color: Theme.focusBlue
                                }
                            }

                            handle: Rectangle {
                                x: volumeSlider.leftPadding
                                    + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                y: volumeSlider.topPadding + (volumeSlider.availableHeight - height) / 2
                                width: 15
                                height: 15
                                radius: 7.5
                                color: volumeSlider.activeFocus ? Theme.focusInk : "#FFFFFF"
                                border.width: 4
                                border.color: Theme.focusBlue
                                scale: volumeSlider.pressed || volumeSlider.activeFocus ? 1.15 : 1

                                Behavior on scale { NumberAnimation { duration: 110 } }
                            }
                        }

                        Text {
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(trimWindow.exportVolume * 100) + "%"
                            color: Theme.inkDim
                            font.family: Theme.mono
                            font.pixelSize: 11
                        }
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
                        && trimWindow.loadError.length === 0
                        && !backend.processingTrim
                        && !backend.recording
                        && trimRange.second.value - trimRange.first.value >= 0.25
                    text: trimWindow.motionBlur ? "Export blurred copy" : "Export trimmed copy"
                    onClicked: {
                        trimPlayer.pause()
                        trimWindow.closeBlurPreview()
                        backend.exportTrim(
                            trimWindow.sourcePath,
                            trimRange.first.value,
                            trimRange.second.value,
                            trimWindow.motionBlur,
                            trimWindow.motionBlurStrength,
                            trimWindow.muteAudio ? 0 : trimWindow.exportVolume)
                        trimWindow.dismiss()
                    }
                }
            }
        }
    }

    VideoDropZone {
        anchors.fill: parent
        hint: "Drop to open instead"
        onVideoDropped: path => trimWindow.openForSource(path)
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
