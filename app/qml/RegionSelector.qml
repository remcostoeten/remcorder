import QtQuick
import QtQuick.Window

Item {
    id: selector

    signal selected(real x, real y, real width, real height, real ratio)
    signal cancelled()

    readonly property real selectionX: Math.min(anchorX, pointerX)
    readonly property real selectionY: Math.min(anchorY, pointerY)
    readonly property real selectionWidth: Math.abs(pointerX - anchorX)
    readonly property real selectionHeight: Math.abs(pointerY - anchorY)
    readonly property bool active: overlays.active

    property real anchorX: 0
    property real anchorY: 0
    property real pointerX: 0
    property real pointerY: 0
    property real pointerRatio: 1
    property bool dragging: false

    function open() {
        dragging = false
        anchorX = 0
        anchorY = 0
        pointerX = 0
        pointerY = 0
        overlays.active = true
    }

    function cancel() {
        overlays.active = false
        dragging = false
        selector.cancelled()
    }

    function commit() {
        const width = selectionWidth
        const height = selectionHeight
        const x = selectionX
        const y = selectionY
        const ratio = pointerRatio
        overlays.active = false
        dragging = false
        if (width < 8 || height < 8)
            selector.cancelled()
        else
            selector.selected(x, y, width, height, ratio)
    }

    component Shade: Rectangle {
        color: "#BC030304"
    }

    Instantiator {
        id: overlays

        active: false
        model: Qt.application.screens

        delegate: Window {
            id: overlay

            required property var modelData

            readonly property real localX: selector.selectionX - modelData.virtualX
            readonly property real localY: selector.selectionY - modelData.virtualY

            screen: modelData
            x: modelData.virtualX
            y: modelData.virtualY
            width: modelData.width
            height: modelData.height
            visible: true
            color: "transparent"
            title: "Select a capture region"
            transientParent: null
            flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool

            Component.onCompleted: requestActivate()

            Item {
                id: canvas

                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: selector.cancel()
                Keys.onReturnPressed: selector.commit()

                Shade {
                    x: 0
                    y: 0
                    width: canvas.width
                    height: Math.max(0, Math.min(canvas.height, overlay.localY))
                }
                Shade {
                    x: 0
                    y: Math.max(0, overlay.localY + selector.selectionHeight)
                    width: canvas.width
                    height: Math.max(0, canvas.height - y)
                }
                Shade {
                    x: 0
                    y: Math.max(0, overlay.localY)
                    width: Math.max(0, Math.min(canvas.width, overlay.localX))
                    height: selector.selectionHeight
                }
                Shade {
                    x: Math.max(0, overlay.localX + selector.selectionWidth)
                    y: Math.max(0, overlay.localY)
                    width: Math.max(0, canvas.width - x)
                    height: selector.selectionHeight
                }

                Rectangle {
                    id: marquee

                    x: overlay.localX
                    y: overlay.localY
                    width: selector.selectionWidth
                    height: selector.selectionHeight
                    visible: selector.dragging
                    color: "transparent"
                    border.width: 1
                    border.color: "#E34C26"

                    Rectangle {
                        anchors.fill: parent
                        color: "#14E34C26"
                    }

                    Repeater {
                        model: [
                            { hx: 0, hy: 0 },
                            { hx: 1, hy: 0 },
                            { hx: 0, hy: 1 },
                            { hx: 1, hy: 1 }
                        ]

                        delegate: Rectangle {
                            required property var modelData

                            width: 7
                            height: 7
                            radius: 2
                            color: "#E34C26"
                            x: modelData.hx * marquee.width - width / 2
                            y: modelData.hy * marquee.height - height / 2
                        }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 8
                        width: dimensions.implicitWidth + 16
                        height: 24
                        radius: 7
                        color: "#F2111113"
                        border.width: 1
                        border.color: "#2E2E35"

                        Text {
                            id: dimensions

                            anchors.centerIn: parent
                            text: Math.round(selector.selectionWidth) + " × " + Math.round(selector.selectionHeight)
                            color: "#FAFAFA"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 12
                        }
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 48
                    visible: !selector.dragging
                    width: hint.implicitWidth + 28
                    height: 40
                    radius: 12
                    color: "#F2111113"
                    border.width: 1
                    border.color: "#2E2E35"

                    Text {
                        id: hint

                        anchors.centerIn: parent
                        text: "Drag to select a region  ·  Esc to cancel"
                        color: "#FAFAFA"
                        font.family: "Inter"
                        font.pixelSize: 13
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.CrossCursor

                    onPressed: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            selector.cancel()
                            return
                        }
                        canvas.forceActiveFocus()
                        selector.pointerRatio = overlay.modelData.devicePixelRatio
                        selector.anchorX = mouse.x + overlay.modelData.virtualX
                        selector.anchorY = mouse.y + overlay.modelData.virtualY
                        selector.pointerX = selector.anchorX
                        selector.pointerY = selector.anchorY
                        selector.dragging = true
                    }

                    onPositionChanged: mouse => {
                        if (!selector.dragging)
                            return
                        selector.pointerX = mouse.x + overlay.modelData.virtualX
                        selector.pointerY = mouse.y + overlay.modelData.virtualY
                    }

                    onReleased: mouse => {
                        if (mouse.button === Qt.LeftButton && selector.dragging)
                            selector.commit()
                    }
                }
            }
        }
    }
}
