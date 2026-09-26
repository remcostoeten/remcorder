import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: sheet

    signal trimRequested(string path)

    function baseName(path) {
        const parts = String(path).split("/")
        return parts[parts.length - 1]
    }

    parent: Overlay.overlay
    x: 0
    y: 0
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    padding: 0
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 130 }
        NumberAnimation {
            property: "scale"
            from: 0.97
            to: 1
            duration: 190
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 110 }
    }

    background: Rectangle { color: Theme.canvas }
    Overlay.modal: Rectangle { color: "#C0030304" }

    VideoDropZone {
        parent: sheet.contentItem.parent
        anchors.fill: parent
        enabled: sheet.opened
        onVideoDropped: path => {
            sheet.close()
            sheet.trimRequested(path)
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            Layout.leftMargin: 18
            Layout.rightMargin: 10
            spacing: 9

            Glyph {
                Layout.preferredWidth: 15
                Layout.preferredHeight: 15
                name: "library"
                tint: Theme.inkDim
            }
            Text {
                Layout.fillWidth: true
                text: "Library"
                color: Theme.ink
                font.family: Theme.sans
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            WindowButton {
                glyph: "close"
                Accessible.name: "Close library"
                onClicked: sheet.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.strokeSoft
        }

        ListView {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 12
            clip: true
            spacing: 4
            model: backend.recentRecordings

            ScrollBar.vertical: ScrollBar {
                id: listBar
                width: 8
                policy: ScrollBar.AsNeeded

                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: listBar.pressed ? Theme.inkDim : "#3A3A44"
                    opacity: listBar.active ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: 220 } }
                }
                background: Item {}
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                readonly property bool isLatest: index === 0

                width: list.width - (list.ScrollBar.vertical.visible ? 12 : 0)
                height: 52
                radius: 10
                color: rowHover.hovered ? Theme.surface : "transparent"
                border.width: 1
                border.color: rowHover.hovered ? Theme.stroke : "transparent"

                Behavior on color { ColorAnimation { duration: 130 } }
                Behavior on border.color { ColorAnimation { duration: 130 } }

                HoverHandler { id: rowHover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 7
                        Layout.preferredHeight: 7
                        radius: 3.5
                        color: row.isLatest ? Theme.signal : Theme.inkFaint
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: sheet.baseName(row.modelData)
                            color: Theme.ink
                            font.family: Theme.sans
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideMiddle
                        }
                        Text {
                            visible: row.isLatest
                            text: "Most recent"
                            color: Theme.inkFaint
                            font.family: Theme.sans
                            font.pixelSize: 11
                        }
                    }

                    GhostButton {
                        opacity: rowHover.hovered ? 1 : 0.75
                        implicitWidth: 34
                        implicitHeight: 30
                        glyph: "open"
                        Accessible.name: "Open recording"
                        onClicked: backend.openRecentRecording(row.modelData)

                        Behavior on opacity { NumberAnimation { duration: 130 } }
                    }
                    GhostButton {
                        opacity: rowHover.hovered ? 1 : 0.75
                        implicitWidth: 34
                        implicitHeight: 30
                        glyph: "reveal"
                        Accessible.name: "Show in folder"
                        onClicked: backend.revealRecording(row.modelData)

                        Behavior on opacity { NumberAnimation { duration: 130 } }
                    }
                    GhostButton {
                        opacity: rowHover.hovered ? 1 : 0.75
                        visible: row.isLatest
                        implicitWidth: 34
                        implicitHeight: 30
                        glyph: "copy"
                        Accessible.name: "Copy path"
                        onClicked: backend.copyLastOutputPath()

                        Behavior on opacity { NumberAnimation { duration: 130 } }
                    }
                    GhostButton {
                        opacity: rowHover.hovered ? 1 : 0.75
                        implicitWidth: 34
                        implicitHeight: 30
                        glyph: "trim"
                        enabled: !backend.processingTrim
                        Accessible.name: "Trim recording"
                        onClicked: {
                            sheet.close()
                            sheet.trimRequested(row.modelData)
                        }

                        Behavior on opacity { NumberAnimation { duration: 130 } }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                visible: list.count === 0
                spacing: 8

                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "library"
                    width: 26
                    height: 26
                    tint: Theme.inkFaint
                    opacity: 0.6
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No recordings yet"
                    color: Theme.inkDim
                    font.family: Theme.sans
                    font.pixelSize: 13
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.strokeSoft
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 8

            GhostButton {
                visible: backend.lastTrimmedOutputFile.length > 0
                implicitHeight: 34
                glyph: "check"
                text: "Trimmed copy"
                textColor: Theme.successInk
                onClicked: backend.openLastTrimmedRecording()
            }

            Item { Layout.fillWidth: true }

            GhostButton {
                implicitHeight: 34
                glyph: "folder"
                text: "Save folder"
                Accessible.name: "Choose where recordings are saved"
                onClicked: backend.chooseOutputDirectory()
            }
            GhostButton {
                implicitHeight: 34
                glyph: "plus"
                text: "Edit a video…"
                enabled: !backend.processingTrim
                onClicked: {
                    const path = backend.chooseVideoToTrim()
                    if (path.length > 0) {
                        sheet.close()
                        sheet.trimRequested(path)
                    }
                }
            }
        }
    }
}
