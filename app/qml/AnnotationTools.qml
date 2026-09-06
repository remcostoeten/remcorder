import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Item {
    id: tools

    property alias penEnabled: preferences.penEnabled
    property alias holdSeconds: preferences.holdSeconds
    property alias reducedMotion: preferences.reducedMotion

    Settings {
        id: preferences
        objectName: "annotationPreferences"
        category: "Annotations"
        property bool penEnabled: true
        property int holdSeconds: 5
        property real penWidth: 4
        property color penColor: "#FF6257"
        property bool reducedMotion: false
    }

    Binding {
        target: annotationInput
        property: "enabled"
        value: preferences.penEnabled
    }

    Instantiator {
        model: Qt.application.screens

        delegate: Window {
            id: overlay
            required property var modelData
            property bool ready: false
            property double lastRightPress: 0

            screen: modelData
            x: modelData.virtualX
            y: modelData.virtualY
            width: modelData.width
            height: modelData.height
            visible: ready && preferences.penEnabled && (annotationInput.active || canvas.hasStrokes)
            color: "transparent"
            title: "Remcorder Annotations"
            transientParent: null
            flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
                | Qt.WindowDoesNotAcceptFocus
                | (annotationInput.active ? 0 : Qt.WindowTransparentForInput)

            Component.onCompleted: {
                windowChrome.pinAbove(overlay, WindowChrome.AnchorTop | WindowChrome.AnchorLeft, 0, 0, 0, 0)
                ready = true
            }

            function openPalette(px, py) {
                canvas.finish()
                penMenu.x = Math.max(8, Math.min(px, width - penMenu.width - 8))
                penMenu.y = Math.max(8, Math.min(py, height - penMenu.height - 8))
                penMenu.visible = true
                lastRightPress = 0
            }

            Connections {
                target: annotationInput
                function onActiveChanged() {
                    if (!annotationInput.active) {
                        canvas.finish()
                        penMenu.visible = false
                        overlay.lastRightPress = 0
                    }
                }
                function onClearRequested() {
                    canvas.clear()
                    penMenu.visible = false
                }
            }

            AnnotationCanvas {
                id: canvas
                anchors.fill: parent
            }

            MouseArea {
                id: drawing
                anchors.fill: parent
                enabled: annotationInput.active
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: penMenu.visible ? Qt.ArrowCursor : Qt.CrossCursor
                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        const now = Date.now()
                        if (overlay.lastRightPress > 0 && now - overlay.lastRightPress <= 350)
                            overlay.openPalette(mouse.x, mouse.y)
                        else
                            overlay.lastRightPress = now
                    } else if (penMenu.visible) {
                        penMenu.visible = false
                    } else {
                        overlay.lastRightPress = 0
                        canvas.begin(mouse.x, mouse.y, preferences.penColor,
                                     preferences.penWidth, preferences.holdSeconds, preferences.reducedMotion)
                    }
                }
                onPositionChanged: mouse => {
                    if (pressedButtons & Qt.LeftButton)
                        canvas.append(mouse.x, mouse.y)
                }
                onReleased: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        canvas.append(mouse.x, mouse.y)
                        canvas.finish()
                    }
                }
                onCanceled: canvas.finish()
            }

            Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 24
                visible: annotationInput.active
                width: modeLabel.implicitWidth + 32
                height: 40
                radius: 12
                color: Theme.surface
                border.color: preferences.penColor

                Text {
                    id: modeLabel
                    objectName: "annotationModeLabel"
                    anchors.centerIn: parent
                    text: "Drawing mode · double-tap left Shift to exit"
                    color: Theme.ink
                    font.family: Theme.sans
                    font.pixelSize: 12
                }
            }

            Rectangle {
                id: penMenu
                objectName: "annotationPalette"
                visible: false
                width: 264
                height: controls.implicitHeight + 28
                radius: 14
                color: Theme.surface
                border.color: Theme.strokeHi

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: controls
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Text {
                        text: "Annotation pen"
                        color: Theme.ink
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: ["#FF6257", "#FFBE45", "#F9EF69", "#58D68D", "#5EA8FF", "#BC8CFF", "#FFFFFF"]
                            delegate: AbstractButton {
                                required property string modelData
                                objectName: "penColor" + modelData
                                implicitWidth: 28
                                implicitHeight: 28
                                Accessible.name: "Pen color " + modelData
                                onClicked: {
                                    preferences.penColor = modelData
                                    penMenu.visible = false
                                }
                                background: Rectangle {
                                    radius: 14
                                    color: parent.modelData
                                    border.width: preferences.penColor.toString() === parent.modelData.toLowerCase() ? 3 : 0
                                    border.color: Theme.focusInk
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            Rectangle {
                                anchors.centerIn: parent
                                width: preferences.penWidth
                                height: width
                                radius: width / 2
                                color: preferences.penColor
                            }
                        }
                        Text {
                            text: Math.round(preferences.penWidth) + " px · scroll to resize"
                            color: Theme.inkDim
                            font.family: Theme.sans
                            font.pixelSize: 11
                        }
                    }

                    RowLayout {
                        Text {
                            Layout.fillWidth: true
                            text: "Visible for"
                            color: Theme.inkDim
                            font.family: Theme.sans
                            font.pixelSize: 12
                        }
                        SpinBox {
                            from: 1
                            to: 300
                            value: preferences.holdSeconds
                            onValueModified: preferences.holdSeconds = value
                            Accessible.name: "Drawing duration in seconds"
                        }
                        Text { text: "s"; color: Theme.inkDim }
                    }

                    Text {
                        text: "Double-tap left Shift to exit."
                        color: Theme.inkFaint
                        font.family: Theme.sans
                        font.pixelSize: 10
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: penMenu.visible
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y
                    if (delta !== 0)
                        preferences.penWidth = Math.max(1, Math.min(40, preferences.penWidth + (delta > 0 ? 1 : -1)))
                    wheel.accepted = true
                }
            }
        }
    }
}
