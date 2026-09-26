import QtMultimedia
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: root

    readonly property bool busy: backend.processingTrim
    readonly property bool live: backend.recording || backend.countingDown
    readonly property string mode: backend.captureSource === "portal"
        ? "portal"
        : backend.captureSource === "region" ? "region" : "direct"

    property bool restoreOnStop: true
    property string dismissedRecording: ""
    property bool freshRecording: false

    readonly property int chromeHeight: 46
    readonly property int bodyHeight: chromeHeight + body.implicitHeight + 25

    width: 480
    height: bodyHeight
    minimumHeight: bodyHeight
    maximumHeight: bodyHeight
    visible: !backend.startHidden
    title: "Remcorder"
    color: Theme.canvas
    flags: Qt.Window | Qt.FramelessWindowHint

    Component.onCompleted: {
        if (backend.initialTrimPath.length > 0)
            Qt.callLater(() => trimWindow.openForSource(backend.initialTrimPath))
    }

    onActiveChanged: {
        if (active)
            backend.refreshDevices()
    }

    onClosing: close => {
        if (backend.trayAvailable) {
            close.accepted = false
            root.hide()
        } else {
            Qt.quit()
        }
    }

    onLiveChanged: {
        if (live) {
            restoreOnStop = root.visible
            root.hide()
            pill.show()
        } else {
            pill.hide()
            if (restoreOnStop) {
                root.show()
                root.raise()
                root.requestActivate()
            }
        }
    }

    Connections {
        target: backend
        function onRequestShow() {
            root.show()
            root.raise()
            root.requestActivate()
        }
        function onRecordingSaved(path) {
            root.dismissedRecording = ""
            root.freshRecording = true
            freshTimer.restart()
        }
    }

    Timer {
        id: freshTimer
        interval: 8000
        onTriggered: root.freshRecording = false
    }

    Connections {
        target: singleInstance
        function onShowRequested() {
            root.show()
            root.raise()
            root.requestActivate()
        }
        function onTrimRequested(path) {
            trimWindow.openForSource(path)
        }
    }

    Binding {
        target: backend
        property: "micMonitorEnabled"
        value: backend.microphoneEnabled && root.visible && !backend.recording
    }

    MediaDevices { id: cameras }

    RecordingPill { id: pill }

    AnnotationTools { id: annotations }

    KeystrokeWindow {
        visible: pill.visible && !pill.counting && backend.showKeystrokes
            && backend.keystrokePlacement === "floating"
    }

    WebcamWindow {
        active: backend.webcamEnabled && (root.visible || root.live)
    }

    TrimWindow { id: trimWindow }

    VideoDropZone {
        parent: root.contentItem
        anchors.fill: parent
        enabled: !root.live
        hint: "Drop to trim or edit"
        onVideoDropped: path => trimWindow.openForSource(path)
    }

    LibrarySheet {
        id: library
        onTrimRequested: path => trimWindow.openForSource(path)
    }

    RegionSelector {
        id: regionSelector

        onSelected: (x, y, width, height, ratio) => {
            backend.setCaptureRegionFromRect(x, y, width, height, ratio)
            root.endRegionPicking()
        }
        onCancelled: root.endRegionPicking()
    }

    // The window stays mapped at zero opacity so the app never counts it as its
    // last window and quits while the selection overlay is up.
    function pickCaptureRegion() {
        root.opacity = 0
        Qt.callLater(() => regionSelector.open())
    }

    function endRegionPicking() {
        root.opacity = 1
        root.raise()
        root.requestActivate()
    }

    function shortPath(path) {
        const value = String(path)
        const home = "/home/"
        const slash = value.indexOf("/", home.length)
        if (value.startsWith(home) && slash > 0)
            return "~" + value.slice(slash)
        return value
    }

    header: Rectangle {
        height: root.chromeHeight
        color: Theme.canvas

        DragHandler {
            target: null
            onActiveChanged: {
                if (active)
                    windowChrome.startMove(root)
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 8
            spacing: 9

            Image {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                source: "qrc:/branding/remcorder-128.png"
                sourceSize.width: 128
                sourceSize.height: 128
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Text {
                text: "Remcorder"
                color: Theme.ink
                font.family: Theme.sans
                font.pixelSize: 13
                font.weight: Font.DemiBold
                font.letterSpacing: -0.1
            }

            Rectangle {
                Layout.preferredWidth: 5
                Layout.preferredHeight: 5
                Layout.leftMargin: 2
                radius: 2.5
                color: backend.serviceAvailable ? Theme.success : Theme.amber

                Behavior on color { ColorAnimation { duration: 200 } }

                ToolTip.visible: statusHover.hovered
                ToolTip.text: backend.serviceAvailable
                    ? "Recorder service connected"
                    : "Connecting to the recorder service…"
                ToolTip.delay: 300

                HoverHandler { id: statusHover }
            }

            Item { Layout.fillWidth: true }

            WindowButton {
                glyph: "minimize"
                Accessible.name: "Minimize"
                onClicked: root.showMinimized()
            }
            WindowButton {
                glyph: "close"
                hoverFill: Theme.signal
                hoverInk: "#FFFFFF"
                Accessible.name: backend.trayAvailable ? "Hide to tray" : "Close"
                onClicked: root.close()
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
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 14
        spacing: 11

        Rectangle {
            visible: backend.errorMessage.length > 0
            Layout.fillWidth: true
            implicitHeight: 34
            radius: 9
            color: "#1B1910"
            border.width: 1
            border.color: "#3A3520"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 11
                anchors.rightMargin: 6
                spacing: 8

                Glyph {
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    name: "alert"
                    tint: Theme.amber
                }
                Text {
                    Layout.fillWidth: true
                    text: backend.errorMessage
                    color: "#E4DCB4"
                    font.family: Theme.sans
                    font.pixelSize: 12
                    elide: Text.ElideRight

                    ToolTip.visible: errorHover.hovered
                    ToolTip.text: backend.errorMessage
                    ToolTip.delay: 300

                    HoverHandler { id: errorHover }
                }
                GhostButton {
                    visible: !backend.serviceAvailable
                    implicitWidth: 54
                    implicitHeight: 26
                    text: "Retry"
                    onClicked: backend.startService()
                }
            }
        }

        Segmented {
            Layout.fillWidth: true
            options: [
                { value: "direct", label: "Display", glyph: "monitor" },
                { value: "region", label: "Region", glyph: "region" },
                { value: "portal", label: "Window", glyph: "portal" }
            ]
            current: root.mode
            onPicked: value => {
                if (value === "portal") {
                    backend.captureSource = "portal"
                } else if (value === "region") {
                    backend.captureSource = "region"
                    if (backend.captureRegion.length === 0)
                        root.pickCaptureRegion()
                } else {
                    backend.captureSource = displayCombo.currentValue || "screen"
                }
            }
        }

        DeviceCombo {
            id: displayCombo
            Layout.fillWidth: true
            visible: root.mode === "direct"
            model: backend.monitors
            Component.onCompleted: currentIndex = indexOfValue(backend.captureSource)
            onModelChanged: currentIndex = Math.max(0, indexOfValue(backend.captureSource))
            onActivated: backend.captureSource = currentValue
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            visible: root.mode === "region"
            radius: 9
            color: Theme.canvasLift
            border.width: 1
            border.color: backend.captureRegion.length > 0
                ? Theme.stroke
                : Theme.tintBorder(Theme.amber)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 11
                anchors.rightMargin: 4
                spacing: 8

                Glyph {
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    name: "region"
                    tint: backend.captureRegion.length > 0 ? Theme.inkFaint : Theme.amber
                }
                Text {
                    Layout.fillWidth: true
                    text: backend.captureRegionLabel
                    color: backend.captureRegion.length > 0 ? Theme.ink : Theme.amber
                    font.family: Theme.mono
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                GhostButton {
                    implicitHeight: 28
                    text: backend.captureRegion.length > 0 ? "Reselect" : "Select"
                    onClicked: root.pickCaptureRegion()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            visible: root.mode === "portal"
            radius: 9
            color: Theme.canvasLift
            border.width: 1
            border.color: Theme.stroke

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 11
                anchors.rightMargin: 11
                spacing: 8

                Glyph {
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    name: "portal"
                    tint: Theme.inkFaint
                }
                Text {
                    Layout.fillWidth: true
                    text: "You pick the window when recording starts."
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 7

            Chip {
                id: micChip
                Layout.fillWidth: true
                Layout.preferredWidth: 92
                glyph: "mic"
                label: "Mic"
                checked: backend.microphoneEnabled
                hasMenu: true
                menuOpen: micPopover.opened
                tint: Theme.successInk
                Accessible.name: "Capture microphone"
                onToggled: backend.microphoneEnabled = !backend.microphoneEnabled
                onMenuRequested: micPopover.opened ? micPopover.close() : micPopover.open()
            }

            Chip {
                id: desktopChip
                Layout.fillWidth: true
                Layout.preferredWidth: 92
                glyph: "speaker"
                label: "Audio"
                checked: backend.desktopAudioEnabled
                hasMenu: true
                menuOpen: desktopPopover.opened
                tint: Theme.successInk
                Accessible.name: "Capture desktop audio"
                onToggled: backend.desktopAudioEnabled = !backend.desktopAudioEnabled
                onMenuRequested: desktopPopover.opened ? desktopPopover.close() : desktopPopover.open()
            }

            Chip {
                id: overlaysChip
                Layout.fillWidth: true
                Layout.preferredWidth: 112
                glyph: "cursor"
                label: "Overlays"
                checkable: false
                hasMenu: true
                menuOpen: overlaysPopover.opened
                Accessible.name: "Overlay settings"
                onMenuRequested: overlaysPopover.opened ? overlaysPopover.close() : overlaysPopover.open()
            }

            Chip {
                id: qualityChip
                Layout.fillWidth: true
                Layout.preferredWidth: 128
                glyph: "spark"
                label: backend.qualityPreset === "crisp"
                    ? "Crisp"
                    : backend.qualityPreset === "compact" ? "Compact" : "Balanced"
                checkable: false
                hasMenu: true
                menuOpen: qualityPopover.opened
                Accessible.name: "Recording quality"
                onMenuRequested: qualityPopover.opened ? qualityPopover.close() : qualityPopover.open()
            }
        }

        PrimaryButton {
            Layout.fillWidth: true
            implicitHeight: 48
            readonly property bool regionMissing: root.mode === "region" && backend.captureRegion.length === 0

            enabled: backend.serviceAvailable
                && !root.busy
                && !backend.choosingSource
                && !backend.awaitingFirstFrame
                && !regionMissing
            glyph: root.busy || backend.choosingSource ? "" : "record"
            tint: root.busy ? Theme.focusBlue : Theme.signal
            text: backend.processingTrim
                ? "Exporting trim…  " + backend.trimProgress + "%"
                : backend.choosingSource
                ? "Waiting for your pick…"
                : backend.awaitingFirstFrame
                ? "Warming up the encoder…"
                : regionMissing
                ? "Select a region first"
                : backend.startDelaySeconds > 0
                ? "Start recording in " + backend.startDelaySeconds + "s"
                : "Start recording"
            onClicked: backend.startRecording()
        }

        SavedRecordingCard {
            Layout.fillWidth: true
            visible: !root.live
                && backend.lastOutputFile.length > 0
                && backend.lastOutputFile !== root.dismissedRecording
            path: backend.lastOutputFile
            fresh: root.freshRecording
            onTrimRequested: target => trimWindow.openForSource(target)
            onDismissed: root.dismissedRecording = backend.lastOutputFile
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 11
            spacing: 6

            GhostButton {
                Layout.fillWidth: true
                implicitHeight: 30
                fill: "transparent"
                bordered: false
                glyph: "folder"
                text: root.shortPath(backend.outputDirectory)
                textColor: Theme.inkFaint
                Accessible.name: "Open the folder recordings are saved to"
                onClicked: backend.openOutputDirectory()
            }

            GhostButton {
                implicitHeight: 30
                fill: "transparent"
                bordered: false
                glyph: "library"
                text: backend.recentRecordings.length > 0
                    ? "Library · " + backend.recentRecordings.length
                    : "Library"
                textColor: Theme.inkFaint
                onClicked: library.open()
            }

            GhostButton {
                implicitHeight: 30
                fill: "transparent"
                bordered: false
                glyph: "trim"
                text: "Edit video"
                textColor: Theme.inkFaint
                enabled: !root.busy
                Accessible.name: "Choose a video file to trim or edit"
                onClicked: {
                    const path = backend.chooseVideoToTrim()
                    if (path.length > 0)
                        trimWindow.openForSource(path)
                }
            }
        }
    }

    Popover {
        id: micPopover
        anchorItem: micChip
        width: 288

        contentItem: ColumnLayout {
            spacing: 9

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Microphone"
                    color: Theme.ink
                    font.family: Theme.sans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                ModernSwitch {
                    checked: backend.microphoneEnabled
                    onToggled: backend.microphoneEnabled = checked
                }
            }

            DeviceCombo {
                Layout.fillWidth: true
                enabled: backend.microphoneEnabled
                model: backend.inputDevices
                Component.onCompleted: currentIndex = indexOfValue(backend.inputDevice)
                onModelChanged: currentIndex = Math.max(0, indexOfValue(backend.inputDevice))
                onActivated: backend.inputDevice = currentValue
            }

            LevelMeter {
                Layout.fillWidth: true
                Layout.preferredHeight: 16
                opacity: backend.microphoneEnabled ? 1 : 0.3
                level: backend.micLevel
                peak: backend.micPeak

                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: backend.micGainSupported
                spacing: 9

                Text {
                    text: "Gain"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                }

                Slider {
                    id: gainSlider
                    Layout.fillWidth: true
                    enabled: backend.microphoneEnabled
                    from: 0
                    to: 1.5
                    stepSize: 0.01
                    value: backend.micGain
                    onMoved: backend.micGain = value

                    background: Rectangle {
                        x: gainSlider.leftPadding
                        y: gainSlider.topPadding + (gainSlider.availableHeight - height) / 2
                        width: gainSlider.availableWidth
                        height: 5
                        radius: 2.5
                        color: "#1D1D22"

                        Rectangle {
                            width: gainSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 2.5
                            color: gainSlider.value > 1.0 ? Theme.amber : Theme.focusBlue
                        }
                    }

                    handle: Rectangle {
                        x: gainSlider.leftPadding
                            + gainSlider.visualPosition * (gainSlider.availableWidth - width)
                        y: gainSlider.topPadding + (gainSlider.availableHeight - height) / 2
                        width: 15
                        height: 15
                        radius: 7.5
                        color: gainSlider.activeFocus ? Theme.focusInk : "#FFFFFF"
                        border.width: 4
                        border.color: gainSlider.value > 1.0 ? Theme.amber : Theme.focusBlue
                        scale: gainSlider.pressed || gainSlider.activeFocus ? 1.15 : 1

                        Behavior on scale { NumberAnimation { duration: 110 } }
                    }
                }

                Text {
                    Layout.preferredWidth: 34
                    text: Math.round(backend.micGain * 100) + "%"
                    color: Theme.inkDim
                    font.family: Theme.mono
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignRight
                }
            }

            GhostButton {
                Layout.fillWidth: true
                implicitHeight: 32
                enabled: backend.microphoneEnabled && !backend.recording
                glyph: "headphones"
                text: backend.micPlaybackEnabled
                    ? "Stop listening"
                    : "Listen to yourself"
                fill: backend.micPlaybackEnabled ? "#0C2417" : Theme.canvasLift
                textColor: backend.micPlaybackEnabled ? Theme.successInk : Theme.inkDim
                onClicked: backend.micPlaybackEnabled = !backend.micPlaybackEnabled
            }

            Text {
                Layout.fillWidth: true
                visible: backend.micPlaybackEnabled
                text: "Wear headphones — speakers will feed back."
                color: Theme.inkFaint
                font.family: Theme.sans
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }

    Popover {
        id: desktopPopover
        anchorItem: desktopChip
        width: 288

        contentItem: ColumnLayout {
            spacing: 9

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Desktop audio"
                    color: Theme.ink
                    font.family: Theme.sans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                ModernSwitch {
                    checked: backend.desktopAudioEnabled
                    onToggled: backend.desktopAudioEnabled = checked
                }
            }

            DeviceCombo {
                Layout.fillWidth: true
                enabled: backend.desktopAudioEnabled
                model: backend.outputDevices
                Component.onCompleted: currentIndex = indexOfValue(backend.outputDevice)
                onModelChanged: currentIndex = Math.max(0, indexOfValue(backend.outputDevice))
                onActivated: backend.outputDevice = currentValue
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.strokeSoft }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Sound cues"
                        color: Theme.ink
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        text: "Chime on start and stop."
                        color: Theme.inkFaint
                        font.family: Theme.sans
                        font.pixelSize: 11
                    }
                }
                ModernSwitch {
                    checked: backend.soundCuesEnabled
                    onToggled: backend.soundCuesEnabled = checked
                }
            }
        }
    }

    Popover {
        id: overlaysPopover
        anchorItem: overlaysChip
        width: 288

        contentItem: ColumnLayout {
            spacing: 9

            Text {
                text: "Overlays"
                color: Theme.ink
                font.family: Theme.sans
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 1

                    Text {
                        text: "Show pointer"
                        color: Theme.ink
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Include the cursor in the capture."
                        color: Theme.inkFaint
                        font.family: Theme.sans
                        font.pixelSize: 11
                    }
                }
                ModernSwitch {
                    checked: backend.captureCursor
                    onToggled: backend.captureCursor = checked
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.strokeSoft
                visible: backend.clickHighlightSupported
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: backend.clickHighlightSupported

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 1

                    Text {
                        text: "Highlight clicks"
                        color: Theme.ink
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Rings around the pointer on every click, drawn by KWin while recording."
                        color: Theme.inkFaint
                        font.family: Theme.sans
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
                ModernSwitch {
                    checked: backend.highlightClicks
                    onToggled: backend.highlightClicks = checked
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.strokeSoft }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 1

                    Text {
                        text: "Show keystrokes"
                        color: Theme.ink
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: backend.keystrokeError.length > 0
                            ? "Unavailable: " + backend.keystrokeError
                            : "Key chips while recording; drag the floating strip anywhere. Every key you type is shown, so pause before passwords."
                        color: backend.keystrokeError.length > 0 ? Theme.amber : Theme.inkFaint
                        font.family: Theme.sans
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
                ModernSwitch {
                    checked: backend.showKeystrokes
                    onToggled: backend.showKeystrokes = checked
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: backend.showKeystrokes

                Text {
                    Layout.fillWidth: true
                    text: "Placement"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                }

                Segmented {
                    Layout.preferredWidth: 168
                    implicitHeight: 32
                    options: [
                        { value: "pill", label: "Above pill" },
                        { value: "floating", label: "Floating" }
                    ]
                    current: backend.keystrokePlacement
                    onPicked: value => backend.keystrokePlacement = value
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: backend.showKeystrokes

                Text {
                    Layout.fillWidth: true
                    text: "Keys fade after"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                }

                Segmented {
                    Layout.preferredWidth: 168
                    implicitHeight: 32
                    options: [
                        { value: "1", label: "1s" },
                        { value: "2.5", label: "2.5s" },
                        { value: "5", label: "5s" },
                        { value: "10", label: "10s" }
                    ]
                    current: String(backend.keystrokeHoldSeconds)
                    onPicked: value => backend.keystrokeHoldSeconds = parseFloat(value)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.strokeSoft }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 1

                    Text {
                        text: "Annotation pen"
                        color: Theme.ink
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: annotations.penEnabled && annotationInput.error.length > 0
                            ? annotationInput.error
                            : "Double-tap left Shift to toggle drawing. Double right-click for colors; scroll for size."
                        color: annotationInput.error.length > 0 ? Theme.amber : Theme.inkFaint
                        font.family: Theme.sans
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
                ModernSwitch {
                    checked: annotations.penEnabled
                    onToggled: annotations.penEnabled = checked
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: annotations.penEnabled
                Text {
                    Layout.fillWidth: true
                    text: "Drawings stay (seconds)"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                }
                SpinBox {
                    from: 1
                    to: 300
                    value: annotations.holdSeconds
                    editable: true
                    onValueModified: annotations.holdSeconds = value
                    Accessible.name: "Drawing duration in seconds"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: annotations.penEnabled
                Text {
                    Layout.fillWidth: true
                    text: "Fade drawings without path motion"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                }
                ModernSwitch {
                    checked: annotations.reducedMotion
                    onToggled: annotations.reducedMotion = checked
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.strokeSoft }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 1

                    Text {
                        text: "Webcam bubble"
                        color: Theme.ink
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "A camera window pinned above everything, so the capture records it. Drag it anywhere; region capture only keeps it when it sits inside the region."
                        color: Theme.inkFaint
                        font.family: Theme.sans
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
                ModernSwitch {
                    checked: backend.webcamEnabled
                    onToggled: backend.webcamEnabled = checked
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: backend.webcamEnabled

                Text {
                    Layout.fillWidth: true
                    text: "Shape"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                }

                Segmented {
                    Layout.preferredWidth: 168
                    implicitHeight: 32
                    options: [
                        { value: "circle", label: "Circle" },
                        { value: "square", label: "Square" }
                    ]
                    current: backend.webcamShape
                    onPicked: value => backend.webcamShape = value
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: backend.webcamEnabled

                Text {
                    Layout.fillWidth: true
                    text: "Corner"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                }

                GridLayout {
                    columns: 2
                    columnSpacing: 4
                    rowSpacing: 4

                    Repeater {
                        model: [
                            { value: "topLeft", name: "Top left", right: false, bottom: false },
                            { value: "topRight", name: "Top right", right: true, bottom: false },
                            { value: "bottomLeft", name: "Bottom left", right: false, bottom: true },
                            { value: "bottomRight", name: "Bottom right", right: true, bottom: true }
                        ]

                        delegate: Rectangle {
                            id: cornerCell
                            required property var modelData

                            readonly property bool active: backend.webcamCorner === modelData.value

                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 28
                            radius: 7
                            color: active ? Theme.surfaceTop : cornerHover.hovered ? Theme.surfaceHi : Theme.canvasLift
                            border.width: 1
                            border.color: active ? Theme.strokeHi : Theme.stroke

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            activeFocusOnTab: true
                            Keys.onSpacePressed: backend.webcamCorner = modelData.value
                            Keys.onReturnPressed: backend.webcamCorner = modelData.value
                            Keys.onEnterPressed: backend.webcamCorner = modelData.value

                            FocusRing {}

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 2
                                color: cornerCell.active ? Theme.ink : Theme.inkFaint
                                x: cornerCell.modelData.right ? parent.width - width - 5 : 5
                                y: cornerCell.modelData.bottom ? parent.height - height - 5 : 5

                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            HoverHandler { id: cornerHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: backend.webcamCorner = cornerCell.modelData.value }

                            Accessible.role: Accessible.Button
                            Accessible.name: "Webcam in " + modelData.name.toLowerCase() + " corner"
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: backend.webcamEnabled

                Text {
                    Layout.fillWidth: true
                    text: "Size"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                }

                Segmented {
                    Layout.preferredWidth: 200
                    implicitHeight: 32
                    options: [
                        { value: "small", label: "S" },
                        { value: "medium", label: "M" },
                        { value: "large", label: "L" }
                    ]
                    current: backend.webcamSize
                    onPicked: value => backend.webcamSize = value
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: backend.webcamEnabled

                Text {
                    Layout.fillWidth: true
                    text: "Mirror"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                }

                ModernSwitch {
                    checked: backend.webcamMirrored
                    onToggled: backend.webcamMirrored = checked
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: backend.webcamEnabled && cameras.videoInputs.length > 1

                Text {
                    text: "Camera"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 12
                }

                DeviceCombo {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    textRole: "description"
                    valueRole: "id"
                    model: cameras.videoInputs
                    currentIndex: {
                        const inputs = cameras.videoInputs
                        for (let i = 0; i < inputs.length; ++i) {
                            if (inputs[i].id === backend.webcamDevice)
                                return i
                        }
                        return 0
                    }
                    onActivated: backend.webcamDevice = String(currentValue)
                }
            }
        }
    }

    Popover {
        id: qualityPopover
        anchorItem: qualityChip
        width: 296

        contentItem: ColumnLayout {
            spacing: 9

            Text {
                text: "Recording"
                color: Theme.ink
                font.family: Theme.sans
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Text {
                text: "Quality"
                color: Theme.inkDim
                font.family: Theme.sans
                font.pixelSize: 12
            }

            Segmented {
                Layout.fillWidth: true
                implicitHeight: 36
                options: [
                    { value: "balanced", label: "Balanced" },
                    { value: "crisp", label: "Crisp" },
                    { value: "compact", label: "Compact" }
                ]
                current: backend.qualityPreset
                onPicked: value => backend.qualityPreset = value
            }

            Text {
                Layout.fillWidth: true
                text: backend.qualityPreset === "crisp"
                    ? "HEVC · 60 FPS · maximum detail"
                    : backend.qualityPreset === "compact"
                        ? "HEVC · 30 FPS · smaller files"
                        : "H.264 · 60 FPS · broad compatibility"
                color: Theme.inkDim
                font.family: Theme.mono
                font.pixelSize: 11
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.strokeSoft }

            RowLayout {
                Layout.fillWidth: true
                spacing: 9

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Countdown"
                        color: Theme.ink
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        text: "Delay before capture begins."
                        color: Theme.inkFaint
                        font.family: Theme.sans
                        font.pixelSize: 11
                    }
                }

                Segmented {
                    Layout.preferredWidth: 126
                    implicitHeight: 32
                    options: [
                        { value: "0", label: "Off" },
                        { value: "3", label: "3s" },
                        { value: "5", label: "5s" }
                    ]
                    current: String(backend.startDelaySeconds)
                    onPicked: value => backend.startDelaySeconds = parseInt(value)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.strokeSoft }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: "Shortcuts"
                    color: Theme.ink
                    font.family: Theme.sans
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    Layout.fillWidth: true
                    text: "Bind `remcorderctl toggle` (or pause / stop) to a compositor shortcut to control recordings from anywhere."
                    color: Theme.inkFaint
                    font.family: Theme.sans
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Item {
        parent: Overlay.overlay
        anchors.fill: parent
        z: 1000

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: Theme.stroke
        }
    }
}
