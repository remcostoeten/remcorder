import QtQuick
import QtQuick.Effects
import QtQuick.Window
import QtMultimedia

/**
 * Camera bubble that rides above every other window so the screen capture picks
 * it up. gpu-screen-recorder has no second video input, so the only way to get a
 * webcam into the file is to put one on the screen it is already recording.
 */
Window {
    id: bubble

    /**
     * Drives visibility from outside. The window cannot bind `visible` directly:
     * re-anchoring a layer surface needs the surface torn down and rebuilt, and
     * assigning `visible` in JS would break an incoming binding.
     */
    property bool active: false

    readonly property int margin: 32
    readonly property int diameter: {
        switch (backend.webcamSize) {
        case "small": return 148
        case "large": return 268
        default: return 200
        }
    }
    readonly property bool circular: backend.webcamShape === "circle"
    readonly property bool hasFrames: feed.sourceRect.width > 0 && feed.sourceRect.height > 0

    readonly property int cornerAnchors: {
        switch (backend.webcamCorner) {
        case "topLeft": return WindowChrome.AnchorTop | WindowChrome.AnchorLeft
        case "topRight": return WindowChrome.AnchorTop | WindowChrome.AnchorRight
        case "bottomLeft": return WindowChrome.AnchorBottom | WindowChrome.AnchorLeft
        default: return WindowChrome.AnchorBottom | WindowChrome.AnchorRight
        }
    }

    property bool pinned: false
    property bool rebuilding: false

    width: diameter
    height: diameter
    visible: active && !rebuilding
    color: "transparent"
    title: "Remcorder Webcam"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
    transientParent: null

    function pin() {
        const left = (cornerAnchors & WindowChrome.AnchorLeft) ? margin : 0
        const top = (cornerAnchors & WindowChrome.AnchorTop) ? margin : 0
        const right = (cornerAnchors & WindowChrome.AnchorRight) ? margin : 0
        const bottom = (cornerAnchors & WindowChrome.AnchorBottom) ? margin : 0
        pinned = windowChrome.pinAbove(bubble, cornerAnchors, left, top, right, bottom)
    }

    // Only reached on X11, where the window positions itself and every screen is
    // one virtual desktop.
    function place() {
        const output = screen ?? (Qt.application.screens.length > 0 ? Qt.application.screens[0] : null)
        if (!output)
            return
        const right = output.virtualX + output.width - width - margin
        const bottom = output.virtualY + output.height - height - margin
        x = (cornerAnchors & WindowChrome.AnchorLeft) ? output.virtualX + margin : right
        y = (cornerAnchors & WindowChrome.AnchorTop) ? output.virtualY + margin : bottom
    }

    Component.onCompleted: pin()

    onCornerAnchorsChanged: {
        if (!pinned) {
            place()
            return
        }
        // A layer surface keeps the anchors it was created with, so the corner
        // only changes by dropping the surface and mapping a new one.
        rebuilding = true
        pin()
        remap.restart()
    }

    onVisibleChanged: {
        if (visible && !pinned)
            place()
    }

    Timer {
        id: remap
        interval: 1
        onTriggered: bubble.rebuilding = false
    }

    CaptureSession {
        camera: Camera {
            id: camera

            active: bubble.active
            cameraDevice: {
                const wanted = backend.webcamDevice
                if (wanted.length > 0) {
                    const inputs = devices.videoInputs
                    for (let i = 0; i < inputs.length; ++i) {
                        if (inputs[i].id === wanted)
                            return inputs[i]
                    }
                }
                return devices.defaultVideoInput
            }
        }
        videoOutput: feed
    }

    MediaDevices { id: devices }

    VideoOutput {
        id: feed

        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: false
        transform: Scale {
            origin.x: feed.width / 2
            xScale: backend.webcamMirrored ? -1 : 1
        }
    }

    Rectangle {
        id: mask

        anchors.fill: parent
        radius: bubble.circular ? width / 2 : 20
        color: "black"
        visible: false
        layer.enabled: true
    }

    // A camera that is still opening, or a v4l2 loopback with nothing feeding
    // it, produces no frames at all; without a backing plate the bubble would be
    // an invisible window sitting on top of whatever is underneath.
    Rectangle {
        anchors.fill: parent
        radius: mask.radius
        color: Theme.canvasLift

        Glyph {
            anchors.centerIn: parent
            visible: !bubble.hasFrames
            name: "monitor"
            width: 26
            height: 26
            tint: Theme.inkFaint
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: feed
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }

    Rectangle {
        anchors.fill: parent
        radius: mask.radius
        color: "transparent"
        border.width: 2
        border.color: dragHover.hovered ? Theme.strokeHi : Theme.stroke

        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    HoverHandler { id: dragHover; cursorShape: Qt.SizeAllCursor }

    DragHandler {
        target: null
        onActiveChanged: {
            if (active)
                windowChrome.startMove(bubble)
        }
    }
}
