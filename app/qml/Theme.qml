pragma Singleton

import QtQuick

QtObject {
    readonly property string sans: "Inter"
    readonly property string mono: "JetBrains Mono"

    readonly property color canvas: "#070708"
    readonly property color canvasLift: "#0D0D0F"
    readonly property color surface: "#111113"
    readonly property color surfaceHi: "#18181B"
    readonly property color surfaceTop: "#202024"

    readonly property color stroke: "#242429"
    readonly property color strokeSoft: "#191920"
    readonly property color strokeHi: "#33333A"
    readonly property color specular: "#0DFFFFFF"

    readonly property color ink: "#FAFAFA"
    readonly property color inkDim: "#A1A1AA"
    readonly property color inkFaint: "#6B6B76"

    readonly property color signal: "#E34C26"
    readonly property color amber: "#F1E05A"
    readonly property color success: "#00A152"
    readonly property color successInk: "#35C57C"
    readonly property color focusBlue: "#3178C6"
    readonly property color focusInk: "#5C9BE0"

    function tintSurface(base) {
        return Qt.rgba(base.r, base.g, base.b, 0.14)
    }

    function tintBorder(base) {
        return Qt.rgba(base.r, base.g, base.b, 0.42)
    }
}
