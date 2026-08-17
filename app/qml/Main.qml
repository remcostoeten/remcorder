import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

ApplicationWindow {
    id: root

    readonly property string sans: "Inter"
    readonly property string mono: "JetBrains Mono"

    readonly property color canvas: "#0A0C11"
    readonly property color canvasLift: "#0E1118"
    readonly property color surface: "#13171F"
    readonly property color surfaceHi: "#191E28"
    readonly property color stroke: "#242B37"
    readonly property color strokeSoft: "#1B212B"
    readonly property color ink: "#EEF1F7"
    readonly property color inkDim: "#98A3B5"
    readonly property color inkFaint: "#697384"
    readonly property color signal: "#FF3D57"
    readonly property color amber: "#FFB86B"
    readonly property color teal: "#4FD1C5"
    readonly property color focusBlue: "#7C93FF"

    readonly property bool busy: backend.processingBlur || backend.processingTrim
    readonly property color accent: backend.processingTrim
        ? teal
        : backend.processingBlur
        ? focusBlue
        : backend.recording
        ? (backend.paused ? amber : signal)
        : "#5C6779"

    width: 620
    height: 840
    minimumWidth: 540
    minimumHeight: 700
    visible: !backend.startHidden
    title: "Remcorder"
    color: canvas

    Component.onCompleted: {
        if (backend.initialTrimPath.length > 0)
            Qt.callLater(() => trimDialog.openForSource(backend.initialTrimPath))
    }

    onClosing: close => {
        if (backend.trayAvailable) {
            close.accepted = false
            root.hide()
        }
    }

    Connections {
        target: backend
        function onRequestShow() {
            root.show()
            root.raise()
            root.requestActivate()
        }
    }

    Timer {
        interval: 250
        running: true
        repeat: false
        onTriggered: scroll.contentItem.contentY = 0
    }

    function baseName(path) {
        const parts = String(path).split("/")
        return parts[parts.length - 1]
    }

    component Card: Rectangle {
        radius: 18
        color: root.surface
        border.width: 1
        border.color: root.stroke

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: 1
            radius: 1
            color: "#16FFFFFF"
        }
    }

    component SectionLabel: Text {
        color: root.inkDim
        font.family: root.sans
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1.7
        opacity: 0.85
    }

    component GhostButton: Button {
        id: control

        property color fill: root.surfaceHi
        property color textColor: root.ink
        property color accentColor: root.focusBlue

        implicitHeight: 40
        font.family: root.sans
        font.pixelSize: 13
        font.weight: Font.DemiBold
        hoverEnabled: true

        contentItem: Text {
            text: control.text
            color: control.enabled ? control.textColor : root.inkDim
            opacity: control.enabled ? 1 : 0.5
            font: control.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 12
            color: control.down
                ? Qt.darker(control.fill, 1.25)
                : control.hovered
                ? Qt.lighter(control.fill, 1.22)
                : control.fill
            border.width: 1
            border.color: control.activeFocus
                ? control.accentColor
                : control.hovered ? "#33404F" : root.stroke

            Behavior on color { ColorAnimation { duration: 130 } }
            Behavior on border.color { ColorAnimation { duration: 130 } }
        }

        scale: down ? 0.975 : 1
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    component PrimaryButton: Button {
        id: primary

        property color tint: root.signal

        implicitHeight: 54
        font.family: root.sans
        font.pixelSize: 14
        font.weight: Font.DemiBold
        hoverEnabled: true

        contentItem: Text {
            text: primary.text
            color: primary.enabled ? "#FFFFFF" : "#8D96A6"
            font: primary.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: Item {
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 12
                height: parent.height - 4
                radius: 20
                color: primary.tint
                opacity: primary.enabled ? (primary.hovered ? 0.34 : 0.22) : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Rectangle {
                anchors.fill: parent
                radius: 15
                border.width: 1
                border.color: primary.enabled ? Qt.lighter(primary.tint, 1.25) : root.stroke

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: primary.enabled
                            ? (primary.down ? Qt.darker(primary.tint, 1.15) : Qt.lighter(primary.tint, 1.12))
                            : root.surfaceHi
                    }
                    GradientStop {
                        position: 1
                        color: primary.enabled
                            ? (primary.down ? Qt.darker(primary.tint, 1.3) : Qt.darker(primary.tint, 1.12))
                            : root.surface
                    }
                }
            }
        }

        scale: down ? 0.985 : 1
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    component Segmented: Rectangle {
        id: seg

        property var options: []
        property string current: ""
        signal picked(string value)

        readonly property int activeIndex: {
            for (let i = 0; i < options.length; ++i) {
                if (options[i].value === current)
                    return i
            }
            return 0
        }
        readonly property real cellWidth: options.length > 0 ? (width - 8) / options.length : 0

        implicitHeight: 46
        radius: 15
        color: root.canvasLift
        border.width: 1
        border.color: root.stroke

        Rectangle {
            id: thumb
            width: seg.cellWidth
            height: seg.height - 8
            x: 4 + seg.activeIndex * seg.cellWidth
            y: 4
            radius: 11
            border.width: 1
            border.color: "#3A445C"

            gradient: Gradient {
                GradientStop { position: 0; color: "#2B3346" }
                GradientStop { position: 1; color: "#222939" }
            }

            Behavior on x {
                NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
            }
        }

        Row {
            anchors.fill: parent
            anchors.margins: 4

            Repeater {
                model: seg.options

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index

                    width: seg.cellWidth
                    height: seg.height - 8

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        text: cell.modelData.label
                        color: seg.activeIndex === cell.index
                            ? root.ink
                            : hover.hovered ? root.ink : root.inkDim
                        font.family: root.sans
                        font.pixelSize: 13
                        font.weight: seg.activeIndex === cell.index ? Font.DemiBold : Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight

                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: seg.picked(cell.modelData.value) }
                }
            }
        }
    }

    component ModernSwitch: Switch {
        id: toggle

        implicitWidth: 48
        implicitHeight: 28
        hoverEnabled: true

        indicator: Rectangle {
            implicitWidth: 46
            implicitHeight: 26
            x: toggle.width - width
            y: (toggle.height - height) / 2
            radius: 13
            color: toggle.checked ? root.focusBlue : "#2A3140"
            border.width: 1
            border.color: toggle.activeFocus
                ? root.ink
                : toggle.checked ? Qt.lighter(root.focusBlue, 1.2) : "#39414F"

            Rectangle {
                x: toggle.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                radius: 10
                color: toggle.checked ? "#FFFFFF" : "#9AA4B4"
                scale: toggle.hovered ? 1.06 : 1

                Behavior on x {
                    NumberAnimation { duration: 170; easing.type: Easing.OutBack }
                }
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 120 } }
            }

            Behavior on color { ColorAnimation { duration: 150 } }
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    component DeviceCombo: ComboBox {
        id: combo

        implicitHeight: 44
        textRole: "name"
        valueRole: "value"
        font.family: root.sans
        font.pixelSize: 13
        hoverEnabled: true

        contentItem: Text {
            leftPadding: 14
            rightPadding: 36
            text: combo.displayText
            color: root.ink
            font: combo.font
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: 12
            color: combo.hovered ? Qt.lighter(root.canvasLift, 1.2) : root.canvasLift
            border.width: 1
            border.color: combo.activeFocus
                ? root.focusBlue
                : combo.hovered ? "#33404F" : root.stroke

            Behavior on color { ColorAnimation { duration: 130 } }
            Behavior on border.color { ColorAnimation { duration: 130 } }
        }

        indicator: Canvas {
            x: combo.width - width - 15
            y: (combo.height - height) / 2
            width: 11
            height: 7
            rotation: combo.popup.visible ? 180 : 0

            Behavior on rotation {
                NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = root.inkDim
                ctx.lineWidth = 1.6
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(1, 1)
                ctx.lineTo(width / 2, height - 1)
                ctx.lineTo(width - 1, 1)
                ctx.stroke()
            }
        }

        popup: Popup {
            y: combo.height + 6
            width: combo.width
            implicitHeight: Math.min(contentItem.implicitHeight + 12, 300)
            padding: 6

            enter: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 }
                NumberAnimation {
                    property: "scale"
                    from: 0.97
                    to: 1
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
            exit: Transition {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 }
            }

            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
                ScrollIndicator.vertical: ScrollIndicator {}
            }

            background: Rectangle {
                radius: 14
                color: root.surfaceHi
                border.width: 1
                border.color: root.stroke
            }
        }

        delegate: ItemDelegate {
            id: option
            required property var model
            required property int index

            width: combo.width - 12
            height: 40
            highlighted: combo.highlightedIndex === index

            contentItem: RowLayout {
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: option.model.name
                    color: root.ink
                    font: combo.font
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                Rectangle {
                    visible: combo.currentIndex === option.index
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: root.focusBlue
                }
            }

            background: Rectangle {
                radius: 10
                color: option.highlighted ? "#2A3244" : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
            }
        }
    }

    component LevelMeter: Rectangle {
        id: meter

        property real level: 0
        property real peak: 0

        implicitHeight: 10
        radius: 5
        color: root.canvasLift
        border.width: 1
        border.color: root.stroke
        clip: true

        Rectangle {
            width: Math.max(0, (parent.width - 2) * Math.min(1, meter.level))
            height: parent.height - 2
            x: 1
            y: 1
            radius: 4
            color: meter.level > 0.92 ? root.signal : meter.level > 0.72 ? root.amber : root.teal

            Behavior on width { NumberAnimation { duration: 55 } }
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Rectangle {
            visible: meter.peak > 0.02
            x: Math.max(1, Math.min(parent.width - 3, (parent.width - 2) * meter.peak))
            y: 1
            width: 2
            height: parent.height - 2
            color: root.ink
            opacity: 0.75

            Behavior on x { NumberAnimation { duration: 90 } }
        }
    }

    component PulseRing: Rectangle {
        property int delay: 0
        property bool active: false

        anchors.centerIn: parent
        width: 22
        height: 22
        radius: 11
        color: "transparent"
        border.width: 1.5
        border.color: root.accent
        opacity: 0

        SequentialAnimation on scale {
            running: parent !== null && active
            loops: Animation.Infinite
            PauseAnimation { duration: delay }
            NumberAnimation { from: 0.8; to: 2.1; duration: 1500; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 1500 - delay }
        }
        SequentialAnimation on opacity {
            running: parent !== null && active
            loops: Animation.Infinite
            PauseAnimation { duration: delay }
            NumberAnimation { from: 0.55; to: 0; duration: 1500 }
            PauseAnimation { duration: 1500 - delay }
        }
    }

    Dialog {
        id: trimDialog

        property string sourcePath: ""
        property bool rangeInitialized: false

        function openForSource(path) {
            sourcePath = path
            rangeInitialized = false
            open()
            trimPlayer.source = "file://" + encodeURI(path)
            trimPlayer.play()
        }

        parent: Overlay.overlay
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        width: Math.min(root.width - 48, 560)
        height: Math.min(root.height - 60, 640)
        modal: true
        padding: 22
        closePolicy: Popup.CloseOnEscape
        onClosed: trimPlayer.stop()

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation {
                property: "scale"
                from: 0.96
                to: 1
                duration: 190
                easing.type: Easing.OutCubic
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 110 }
        }

        background: Rectangle {
            radius: 22
            color: root.surface
            border.width: 1
            border.color: root.stroke

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 1
                height: 1
                color: "#1AFFFFFF"
            }
        }
        Overlay.modal: Rectangle { color: "#B3070910" }

        contentItem: ColumnLayout {
            spacing: 15

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Trim a copy"
                        color: root.ink
                        font.family: root.sans
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "The source video remains unchanged."
                        color: root.inkDim
                        font.family: root.sans
                        font.pixelSize: 12
                    }
                }

                GhostButton {
                    text: "✕"
                    implicitWidth: 38
                    implicitHeight: 38
                    Accessible.name: "Close trim editor"
                    onClicked: trimDialog.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(270, width * 9 / 16)
                radius: 14
                color: "#06070B"
                border.width: 1
                border.color: root.strokeSoft
                clip: true

                VideoOutput {
                    id: trimVideo
                    anchors.fill: parent
                    anchors.margins: 1
                    fillMode: VideoOutput.PreserveAspectFit
                }
            }

            MediaPlayer {
                id: trimPlayer
                videoOutput: trimVideo
                audioOutput: AudioOutput { muted: true }
                onDurationChanged: function() {
                    if (duration > 0 && !trimDialog.rangeInitialized) {
                        const seconds = duration / 1000
                        Qt.callLater(function() {
                            trimRange.first.value = 0
                            trimRange.second.value = seconds
                            trimPlayer.pause()
                            trimPlayer.position = 0
                            trimDialog.rangeInitialized = true
                        })
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                GhostButton {
                    text: trimPlayer.playbackState === MediaPlayer.PlayingState
                        ? "❚❚  Pause" : "▶  Play"
                    implicitWidth: 108
                    onClicked: {
                        if (trimPlayer.playbackState === MediaPlayer.PlayingState)
                            trimPlayer.pause()
                        else
                            trimPlayer.play()
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: backend.formatDuration(Math.floor(trimPlayer.position / 1000))
                    color: root.inkDim
                    font.family: root.mono
                    font.pixelSize: 13
                }
            }

            RangeSlider {
                id: trimRange
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                from: 0
                to: Math.max(0.25, trimPlayer.duration / 1000)
                stepSize: 0.1
                first.onMoved: trimPlayer.position = first.value * 1000
                second.onMoved: trimPlayer.position = second.value * 1000

                background: Item {
                    x: trimRange.leftPadding
                    y: (trimRange.height - height) / 2
                    width: trimRange.availableWidth
                    height: 20

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 6
                        radius: 3
                        color: "#20262F"
                    }
                    Rectangle {
                        x: trimRange.first.visualPosition * parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0,
                            (trimRange.second.visualPosition
                             - trimRange.first.visualPosition) * parent.width)
                        height: 6
                        radius: 3

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: root.focusBlue }
                            GradientStop { position: 1; color: root.teal }
                        }
                    }
                }
                first.handle: Rectangle {
                    x: trimRange.leftPadding
                        + trimRange.first.visualPosition
                        * (trimRange.availableWidth - width)
                    y: (trimRange.height - height) / 2
                    width: 20
                    height: 20
                    radius: 10
                    color: "#FFFFFF"
                    border.width: 4
                    border.color: root.focusBlue
                    scale: trimRange.first.pressed ? 1.15 : 1

                    Behavior on scale { NumberAnimation { duration: 110 } }
                }
                second.handle: Rectangle {
                    x: trimRange.leftPadding
                        + trimRange.second.visualPosition
                        * (trimRange.availableWidth - width)
                    y: (trimRange.height - height) / 2
                    width: 20
                    height: 20
                    radius: 10
                    color: "#FFFFFF"
                    border.width: 4
                    border.color: root.teal
                    scale: trimRange.second.pressed ? 1.15 : 1

                    Behavior on scale { NumberAnimation { duration: 110 } }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "IN  " + backend.formatDuration(Math.floor(trimRange.first.value))
                    color: root.inkDim
                    font.family: root.mono
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: backend.formatDuration(
                        Math.max(0, Math.floor(trimRange.second.value - trimRange.first.value)))
                        + " selected"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "OUT  " + backend.formatDuration(Math.floor(trimRange.second.value))
                    color: root.inkDim
                    font.family: root.mono
                    font.pixelSize: 11
                }
            }

            Text {
                Layout.fillWidth: true
                text: trimDialog.sourcePath
                color: root.inkDim
                font.family: root.sans
                font.pixelSize: 11
                opacity: 0.75
                elide: Text.ElideMiddle
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                GhostButton {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    text: "Cancel"
                    onClicked: trimDialog.close()
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    tint: root.focusBlue
                    enabled: trimDialog.rangeInitialized
                        && trimRange.second.value - trimRange.first.value >= 0.25
                    text: "Export trimmed copy"
                    onClicked: {
                        trimPlayer.pause()
                        backend.exportTrim(
                            trimDialog.sourcePath,
                            trimRange.first.value,
                            trimRange.second.value)
                        trimDialog.close()
                    }
                }
            }
        }
    }

    header: Rectangle {
        height: 76
        color: root.canvas

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 26
            anchors.rightMargin: 22
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 12
                color: root.surfaceHi
                border.width: 1
                border.color: root.stroke

                Rectangle {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    radius: 5
                    color: root.signal
                    opacity: backend.recording && !backend.paused ? 1 : 0.75

                    SequentialAnimation on opacity {
                        running: backend.recording && !backend.paused
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.35; duration: 750; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 0.35; to: 1; duration: 750; easing.type: Easing.InOutQuad }
                    }
                }
            }

            ColumnLayout {
                spacing: 1

                Text {
                    text: "Remcorder"
                    color: root.ink
                    font.family: root.sans
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.2
                }
                Text {
                    text: backend.serviceAvailable ? "Wayland capture ready" : "Connecting to recorder…"
                    color: backend.serviceAvailable ? root.inkDim : root.amber
                    font.family: root.sans
                    font.pixelSize: 11
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredHeight: 26
                Layout.preferredWidth: statusPill.implicitWidth + 22
                radius: 13
                color: backend.serviceAvailable ? "#14202A" : "#2A2116"
                border.width: 1
                border.color: backend.serviceAvailable ? "#1F3A44" : "#4A3A22"

                RowLayout {
                    id: statusPill
                    anchors.centerIn: parent
                    spacing: 7

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: backend.serviceAvailable ? root.teal : root.amber
                    }
                    Text {
                        text: backend.serviceAvailable ? "Service online" : "Offline"
                        color: backend.serviceAvailable ? root.teal : root.amber
                        font.family: root.sans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            GhostButton {
                text: "↻"
                implicitWidth: 40
                font.pixelSize: 15
                Accessible.name: "Refresh displays and audio devices"
                onClicked: backend.refreshDevices()
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: root.strokeSoft
        }
    }

    footer: Rectangle {
        visible: !backend.recording
        height: visible ? 88 : 0
        color: root.canvas

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: root.strokeSoft
        }

        PrimaryButton {
            anchors.fill: parent
            anchors.leftMargin: 26
            anchors.rightMargin: 26
            anchors.topMargin: 16
            anchors.bottomMargin: 18
            enabled: backend.serviceAvailable && !root.busy
            tint: root.busy ? root.focusBlue : root.signal
            text: backend.processingTrim
                ? "Exporting trim…  " + backend.trimProgress + "%"
                : backend.processingBlur
                ? "Creating blurred copy…  " + backend.blurProgress + "%"
                : "●   Start recording"
            onClicked: backend.startRecording()
        }
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ScrollBar.vertical: ScrollBar {
            id: bar
            width: 10
            policy: ScrollBar.AsNeeded

            contentItem: Rectangle {
                implicitWidth: 5
                radius: 3
                color: bar.pressed ? root.inkDim : "#39414F"
                opacity: bar.active ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 220 } }
                Behavior on color { ColorAnimation { duration: 130 } }
            }
            background: Item {}
        }

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 20

            Item { Layout.preferredHeight: 4 }

            Card {
                visible: backend.recording || root.busy
                Layout.leftMargin: 26
                Layout.rightMargin: 26
                Layout.fillWidth: true
                implicitHeight: heroContent.implicitHeight + 36
                color: backend.recording || root.busy ? root.surfaceHi : root.surface
                border.color: backend.recording || root.busy
                    ? Qt.darker(root.accent, 2.4)
                    : root.stroke

                Behavior on color { ColorAnimation { duration: 220 } }
                Behavior on border.color { ColorAnimation { duration: 220 } }

                ColumnLayout {
                    id: heroContent
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Item {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44

                            PulseRing {
                                active: backend.recording && !backend.paused
                                delay: 0
                            }
                            PulseRing {
                                active: backend.recording && !backend.paused
                                delay: 750
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                radius: backend.paused ? 6 : 11
                                color: root.accent

                                Behavior on radius {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }
                                Behavior on color { ColorAnimation { duration: 220 } }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: backend.processingTrim
                                    ? "EXPORTING TRIMMED COPY"
                                    : backend.processingBlur
                                    ? "CREATING BLURRED COPY"
                                    : backend.paused
                                    ? "RECORDING PAUSED"
                                    : "CAPTURING"
                                color: root.inkDim
                                font.family: root.sans
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.7
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.busy
                                    ? "Your source recording is safe"
                                    : backend.formatDuration(backend.durationSeconds)
                                color: root.busy ? root.inkDim : root.ink
                                font.family: root.busy ? root.sans : root.mono
                                font.pixelSize: root.busy ? 13 : 28
                                font.weight: root.busy ? Font.Normal : Font.Medium
                                font.letterSpacing: root.busy ? 0 : 1
                                elide: Text.ElideRight
                            }
                        }

                        GhostButton {
                            visible: backend.recording
                            text: backend.paused ? "Resume" : "Pause"
                            implicitWidth: 92
                            implicitHeight: 44
                            onClicked: backend.togglePause()
                        }
                        GhostButton {
                            visible: backend.recording
                            text: "Stop"
                            implicitWidth: 78
                            implicitHeight: 44
                            fill: "#2E1B21"
                            textColor: "#FF97A4"
                            onClicked: backend.stopRecording()
                        }
                    }

                    Rectangle {
                        visible: root.busy
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: "#20262F"

                        Rectangle {
                            width: parent.width
                                * (backend.processingTrim ? backend.trimProgress : backend.blurProgress)
                                / 100
                            height: parent.height
                            radius: 3
                            color: root.accent

                            Behavior on width {
                                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }

            Card {
                visible: backend.errorMessage.length > 0
                Layout.leftMargin: 26
                Layout.rightMargin: 26
                Layout.fillWidth: true
                implicitHeight: errorRow.implicitHeight + 24
                radius: 14
                color: "#231B12"
                border.color: "#4E3D22"

                RowLayout {
                    id: errorRow
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 11

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        radius: 10
                        color: "#3A2C17"

                        Text {
                            anchors.centerIn: parent
                            text: "!"
                            color: root.amber
                            font.family: root.sans
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: backend.errorMessage
                        wrapMode: Text.WordWrap
                        color: "#E7D6B8"
                        font.family: root.sans
                        font.pixelSize: 12
                    }
                    GhostButton {
                        visible: !backend.serviceAvailable
                        text: "Retry"
                        implicitWidth: 70
                        implicitHeight: 34
                        onClicked: backend.startService()
                    }
                }
            }

            ColumnLayout {
                Layout.leftMargin: 26
                Layout.rightMargin: 26
                Layout.fillWidth: true
                spacing: 10

                SectionLabel { text: "CAPTURE" }

                Card {
                    Layout.fillWidth: true
                    implicitHeight: captureColumn.implicitHeight + 28

                    ColumnLayout {
                        id: captureColumn
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 11

                        Segmented {
                            Layout.fillWidth: true
                            options: [
                                { value: "direct", label: "Direct display" },
                                { value: "portal", label: "Choose with portal" }
                            ]
                            current: backend.captureSource === "portal" ? "portal" : "direct"
                            onPicked: value => {
                                if (value === "portal")
                                    backend.captureSource = "portal"
                                else
                                    backend.captureSource = displayCombo.currentValue || "screen"
                            }
                        }

                        DeviceCombo {
                            id: displayCombo
                            Layout.fillWidth: true
                            visible: backend.captureSource !== "portal"
                            model: backend.monitors
                            Component.onCompleted: currentIndex = indexOfValue(backend.captureSource)
                            onModelChanged: currentIndex = Math.max(0, indexOfValue(backend.captureSource))
                            onActivated: backend.captureSource = currentValue
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: backend.captureSource === "portal"
                                    ? "Choose a screen or application when recording starts."
                                    : "Fast, direct capture with minimal GPU overhead."
                                color: root.inkDim
                                font.family: root.sans
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.strokeSoft }

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "Include pointer"
                                color: root.ink
                                font.family: root.sans
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            Item { Layout.fillWidth: true }
                            ModernSwitch {
                                checked: backend.captureCursor
                                onToggled: backend.captureCursor = checked
                                Accessible.name: "Include pointer in recording"
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.strokeSoft }

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "Sound cues"
                                color: root.ink
                                font.family: root.sans
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            Item { Layout.fillWidth: true }
                            ModernSwitch {
                                checked: backend.soundCuesEnabled
                                onToggled: backend.soundCuesEnabled = checked
                                Accessible.name: "Play a sound when recording starts and stops"
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.leftMargin: 26
                Layout.rightMargin: 26
                Layout.fillWidth: true
                spacing: 10

                SectionLabel { text: "SOUND" }

                Card {
                    Layout.fillWidth: true
                    implicitHeight: audioColumn.implicitHeight + 28

                    ColumnLayout {
                        id: audioColumn
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 11

                        RowLayout {
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    text: "Desktop audio"
                                    color: root.ink
                                    font.family: root.sans
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                Text {
                                    text: "System playback captured into the recording."
                                    color: root.inkDim
                                    font.family: root.sans
                                    font.pixelSize: 11
                                }
                            }
                            ModernSwitch {
                                checked: backend.desktopAudioEnabled
                                onToggled: backend.desktopAudioEnabled = checked
                                Accessible.name: "Capture desktop audio"
                            }
                        }
                        DeviceCombo {
                            Layout.fillWidth: true
                            visible: backend.desktopAudioEnabled
                            model: backend.outputDevices
                            Component.onCompleted: currentIndex = indexOfValue(backend.outputDevice)
                            onModelChanged: currentIndex = Math.max(0, indexOfValue(backend.outputDevice))
                            onActivated: backend.outputDevice = currentValue
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.strokeSoft }

                        RowLayout {
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    text: "Microphone"
                                    color: root.ink
                                    font.family: root.sans
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                Text {
                                    text: "Mixed alongside desktop audio."
                                    color: root.inkDim
                                    font.family: root.sans
                                    font.pixelSize: 11
                                }
                            }
                            ModernSwitch {
                                checked: backend.microphoneEnabled
                                onToggled: backend.microphoneEnabled = checked
                                Accessible.name: "Capture microphone"
                            }
                        }
                        DeviceCombo {
                            Layout.fillWidth: true
                            visible: backend.microphoneEnabled
                            model: backend.inputDevices
                            Component.onCompleted: currentIndex = indexOfValue(backend.inputDevice)
                            onModelChanged: currentIndex = Math.max(0, indexOfValue(backend.inputDevice))
                            onActivated: backend.inputDevice = currentValue
                        }

                        Binding {
                            target: backend
                            property: "micMonitorEnabled"
                            value: backend.microphoneEnabled && root.visible
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: backend.microphoneEnabled
                            spacing: 9

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 5

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "Input level"
                                            color: root.inkDim
                                            font.family: root.sans
                                            font.pixelSize: 11
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: backend.micMonitorActive
                                                ? backend.micDeviceName
                                                : "Monitor idle"
                                            color: root.inkFaint
                                            font.family: root.sans
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: 190
                                        }
                                    }

                                    LevelMeter {
                                        Layout.fillWidth: true
                                        level: backend.micLevel
                                        peak: backend.micPeak
                                    }
                                }

                                GhostButton {
                                    text: backend.micPlaybackEnabled ? "Stop listen" : "Listen"
                                    implicitWidth: 104
                                    implicitHeight: 36
                                    enabled: !backend.recording
                                    fill: backend.micPlaybackEnabled ? "#16303A" : root.surfaceHi
                                    textColor: backend.micPlaybackEnabled ? root.teal : root.ink
                                    Accessible.name: "Play the microphone back through the speakers"
                                    onClicked: backend.micPlaybackEnabled = !backend.micPlaybackEnabled
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: backend.micPlaybackEnabled
                                text: "Use headphones while listening back to avoid feedback."
                                color: root.inkFaint
                                font.family: root.sans
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: backend.micGainSupported
                                spacing: 10

                                Text {
                                    text: "Gain"
                                    color: root.inkDim
                                    font.family: root.sans
                                    font.pixelSize: 11
                                }

                                Slider {
                                    id: gainSlider
                                    Layout.fillWidth: true
                                    from: 0
                                    to: 1.5
                                    stepSize: 0.01
                                    value: backend.micGain
                                    onMoved: backend.micGain = value

                                    background: Rectangle {
                                        x: gainSlider.leftPadding
                                        y: gainSlider.topPadding + (gainSlider.availableHeight - height) / 2
                                        width: gainSlider.availableWidth
                                        height: 6
                                        radius: 3
                                        color: "#20262F"

                                        Rectangle {
                                            width: gainSlider.visualPosition * parent.width
                                            height: parent.height
                                            radius: 3
                                            color: gainSlider.value > 1.0 ? root.amber : root.focusBlue
                                        }
                                    }

                                    handle: Rectangle {
                                        x: gainSlider.leftPadding
                                            + gainSlider.visualPosition
                                            * (gainSlider.availableWidth - width)
                                        y: gainSlider.topPadding
                                            + (gainSlider.availableHeight - height) / 2
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: "#FFFFFF"
                                        border.width: 4
                                        border.color: gainSlider.value > 1.0 ? root.amber : root.focusBlue
                                        scale: gainSlider.pressed ? 1.15 : 1

                                        Behavior on scale { NumberAnimation { duration: 110 } }
                                    }
                                }

                                Text {
                                    text: Math.round(backend.micGain * 100) + "%"
                                    color: root.inkDim
                                    font.family: root.mono
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: 38
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.leftMargin: 26
                Layout.rightMargin: 26
                Layout.fillWidth: true
                spacing: 10

                SectionLabel { text: "QUALITY" }

                Card {
                    Layout.fillWidth: true
                    implicitHeight: qualityColumn.implicitHeight + 28

                    ColumnLayout {
                        id: qualityColumn
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 11

                        Segmented {
                            Layout.fillWidth: true
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
                            color: root.inkDim
                            font.family: root.mono
                            font.pixelSize: 11
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.leftMargin: 26
                Layout.rightMargin: 26
                Layout.fillWidth: true
                spacing: 10

                SectionLabel { text: "EXPERIMENTAL" }

                Card {
                    Layout.fillWidth: true
                    implicitHeight: blurColumn.implicitHeight + 28
                    border.color: backend.motionBlurEnabled ? "#2F3E63" : root.stroke

                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    ColumnLayout {
                        id: blurColumn
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 11

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    spacing: 8

                                    Text {
                                        text: "Motion blur copy"
                                        color: root.ink
                                        font.family: root.sans
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 18
                                        Layout.preferredWidth: betaLabel.implicitWidth + 14
                                        radius: 9
                                        color: "#1B2438"
                                        border.width: 1
                                        border.color: "#2F3E63"

                                        Text {
                                            id: betaLabel
                                            anchors.centerIn: parent
                                            text: "BETA"
                                            color: root.focusBlue
                                            font.family: root.sans
                                            font.pixelSize: 9
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 1
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Keep the original and create a second blurred MP4."
                                    color: root.inkDim
                                    font.family: root.sans
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                            }

                            ModernSwitch {
                                checked: backend.motionBlurEnabled
                                onToggled: backend.motionBlurEnabled = checked
                                Accessible.name: "Create an experimental motion blur copy"
                            }
                        }

                        Segmented {
                            visible: backend.motionBlurEnabled
                            Layout.fillWidth: true
                            implicitHeight: 40
                            options: [
                                { value: "subtle", label: "Subtle" },
                                { value: "smooth", label: "Smooth" },
                                { value: "strong", label: "Strong" }
                            ]
                            current: backend.motionBlurStrength
                            onPicked: value => backend.motionBlurStrength = value
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.leftMargin: 26
                Layout.rightMargin: 26
                Layout.fillWidth: true
                spacing: 10

                SectionLabel { text: "SAVE TO" }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Card {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 12
                        color: root.canvasLift

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            text: backend.outputDirectory
                            color: root.inkDim
                            font.family: root.sans
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    GhostButton {
                        text: "Choose…"
                        implicitWidth: 92
                        implicitHeight: 44
                        onClicked: backend.chooseOutputDirectory()
                    }
                    GhostButton {
                        text: "Open"
                        implicitWidth: 68
                        implicitHeight: 44
                        onClicked: backend.openOutputDirectory()
                    }
                }
            }

            ColumnLayout {
                Layout.leftMargin: 26
                Layout.rightMargin: 26
                Layout.fillWidth: true
                spacing: 10
                visible: !backend.recording

                SectionLabel { text: "LIBRARY" }

                Card {
                    Layout.fillWidth: true
                    implicitHeight: libraryColumn.implicitHeight + 28

                    ColumnLayout {
                        id: libraryColumn
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        RowLayout {
                            visible: backend.lastOutputFile.length > 0
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 8
                                Layout.preferredHeight: 8
                                radius: 4
                                color: root.signal
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    text: "Last recording"
                                    color: root.ink
                                    font.family: root.sans
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.baseName(backend.lastOutputFile)
                                    color: root.inkDim
                                    font.family: root.mono
                                    font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                }
                            }
                            GhostButton {
                                text: "Open"
                                implicitWidth: 64
                                implicitHeight: 34
                                onClicked: backend.openLastRecording()
                            }
                            GhostButton {
                                text: "Copy path"
                                implicitWidth: 84
                                implicitHeight: 34
                                onClicked: backend.copyLastOutputPath()
                            }
                            GhostButton {
                                text: "Trim"
                                implicitWidth: 60
                                implicitHeight: 34
                                enabled: !root.busy
                                onClicked: trimDialog.openForSource(backend.lastOutputFile)
                            }
                        }

                        Rectangle {
                            visible: backend.lastOutputFile.length > 0
                                && backend.lastBlurredOutputFile.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: root.strokeSoft
                        }

                        RowLayout {
                            visible: backend.lastBlurredOutputFile.length > 0
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 8
                                Layout.preferredHeight: 8
                                radius: 4
                                color: root.focusBlue
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    text: "Blurred copy"
                                    color: root.ink
                                    font.family: root.sans
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.baseName(backend.lastBlurredOutputFile)
                                    color: root.inkDim
                                    font.family: root.mono
                                    font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                }
                            }
                            GhostButton {
                                text: "Open"
                                implicitWidth: 64
                                implicitHeight: 34
                                onClicked: backend.openLastBlurredRecording()
                            }
                            GhostButton {
                                text: "Trim"
                                implicitWidth: 60
                                implicitHeight: 34
                                enabled: !root.busy
                                onClicked: trimDialog.openForSource(backend.lastBlurredOutputFile)
                            }
                        }

                        Rectangle {
                            visible: backend.lastTrimmedOutputFile.length > 0
                                && (backend.lastOutputFile.length > 0
                                    || backend.lastBlurredOutputFile.length > 0)
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: root.strokeSoft
                        }

                        RowLayout {
                            visible: backend.lastTrimmedOutputFile.length > 0 && !backend.processingTrim
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 8
                                Layout.preferredHeight: 8
                                radius: 4
                                color: root.teal
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    text: "Trimmed copy"
                                    color: root.ink
                                    font.family: root.sans
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.baseName(backend.lastTrimmedOutputFile)
                                    color: root.inkDim
                                    font.family: root.mono
                                    font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                }
                            }
                            GhostButton {
                                text: "Open"
                                implicitWidth: 64
                                implicitHeight: 34
                                onClicked: backend.openLastTrimmedRecording()
                            }
                        }

                        Text {
                            visible: backend.lastOutputFile.length === 0
                                && backend.lastBlurredOutputFile.length === 0
                                && backend.lastTrimmedOutputFile.length === 0
                            Layout.fillWidth: true
                            text: "Recordings from this session will appear here."
                            color: root.inkDim
                            font.family: root.sans
                            font.pixelSize: 12
                        }

                        GhostButton {
                            Layout.fillWidth: true
                            implicitHeight: 40
                            enabled: !root.busy
                            fill: root.canvasLift
                            textColor: root.focusBlue
                            text: "Trim another video…"
                            onClicked: {
                                const path = backend.chooseVideoToTrim()
                                if (path.length > 0)
                                    trimDialog.openForSource(path)
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 16 }
        }
    }
}
