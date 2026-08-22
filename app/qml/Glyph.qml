import QtQuick

/**
 * Stroke-drawn 16×16 icon. Set `name` to one of the keys handled in onPaint.
 * Drawing beats an emoji or an icon font here: the app ships no font of its own
 * and colour emoji ignore `color`, which breaks every tinted state.
 */
Canvas {
    id: glyph

    property string name: ""
    property color tint: Theme.ink
    property real weight: 1.5

    implicitWidth: 16
    implicitHeight: 16
    antialiasing: true
    renderStrategy: Canvas.Cooperative

    onTintChanged: requestPaint()
    onNameChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.scale(width / 16, height / 16)
        ctx.strokeStyle = tint
        ctx.fillStyle = tint
        ctx.lineWidth = weight
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        function line(x1, y1, x2, y2) {
            ctx.beginPath()
            ctx.moveTo(x1, y1)
            ctx.lineTo(x2, y2)
            ctx.stroke()
        }

        function poly(points, close, fill) {
            ctx.beginPath()
            ctx.moveTo(points[0], points[1])
            for (let i = 2; i < points.length; i += 2)
                ctx.lineTo(points[i], points[i + 1])
            if (close)
                ctx.closePath()
            if (fill)
                ctx.fill()
            else
                ctx.stroke()
        }

        function roundRect(x, y, w, h, r, fill) {
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.lineTo(x + w - r, y)
            ctx.arcTo(x + w, y, x + w, y + r, r)
            ctx.lineTo(x + w, y + h - r)
            ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
            ctx.lineTo(x + r, y + h)
            ctx.arcTo(x, y + h, x, y + h - r, r)
            ctx.lineTo(x, y + r)
            ctx.arcTo(x, y, x + r, y, r)
            ctx.closePath()
            if (fill)
                ctx.fill()
            else
                ctx.stroke()
        }

        function arc(cx, cy, r, from, to) {
            ctx.beginPath()
            ctx.arc(cx, cy, r, from, to)
            ctx.stroke()
        }

        switch (name) {
        case "mic":
            roundRect(5.8, 1.6, 4.4, 8, 2.2, false)
            ctx.beginPath()
            ctx.arc(8, 8.4, 4.2, 0, Math.PI)
            ctx.stroke()
            line(8, 12.6, 8, 14.4)
            break
        case "speaker":
            poly([2, 6, 5, 6, 8.6, 2.8, 8.6, 13.2, 5, 10, 2, 10], true, false)
            arc(8.9, 8, 2.9, -0.85, 0.85)
            arc(8.9, 8, 5.2, -0.8, 0.8)
            break
        case "cursor":
            poly([4.2, 1.8, 12.4, 9.4, 8.6, 9.8, 10.6, 13.8, 8.9, 14.6,
                  6.9, 10.6, 4.2, 12.8], true, true)
            break
        case "spark":
            poly([8, 1.4, 9.7, 6.3, 14.6, 8, 9.7, 9.7, 8, 14.6, 6.3, 9.7,
                  1.4, 8, 6.3, 6.3], true, true)
            break
        case "monitor":
            roundRect(1.6, 2.8, 12.8, 9, 1.6, false)
            line(5.8, 14.4, 10.2, 14.4)
            break
        case "region":
            poly([4.4, 1.4, 4.4, 11.6, 14.6, 11.6], false, false)
            poly([1.4, 4.4, 11.6, 4.4, 11.6, 14.6], false, false)
            break
        case "portal":
            roundRect(1.6, 2.4, 8.6, 7.2, 1.4, false)
            roundRect(6.2, 6.4, 8.2, 7.2, 1.4, false)
            break
        case "folder":
            poly([1.6, 13, 1.6, 3.6, 6, 3.6, 7.6, 5.6, 14.4, 5.6, 14.4, 13], true, false)
            break
        case "chevron":
            poly([4, 6.4, 8, 10.4, 12, 6.4], false, false)
            break
        case "arrow":
            line(3, 8, 12.2, 8)
            poly([9, 4.6, 12.4, 8, 9, 11.4], false, false)
            break
        case "play":
            poly([5.2, 3, 13, 8, 5.2, 13], true, true)
            break
        case "pause":
            roundRect(4.6, 3.4, 2.4, 9.2, 1.1, true)
            roundRect(9, 3.4, 2.4, 9.2, 1.1, true)
            break
        case "stop":
            roundRect(4, 4, 8, 8, 1.8, true)
            break
        case "record":
            ctx.beginPath()
            ctx.arc(8, 8, 4.4, 0, Math.PI * 2)
            ctx.fill()
            break
        case "close":
            line(4.6, 4.6, 11.4, 11.4)
            line(11.4, 4.6, 4.6, 11.4)
            break
        case "minimize":
            line(4, 8.4, 12, 8.4)
            break
        case "maximize":
            roundRect(3.6, 3.6, 8.8, 8.8, 1.6, false)
            break
        case "restore":
            roundRect(2.8, 5.6, 7.6, 7.6, 1.4, false)
            poly([5.8, 5.4, 5.8, 2.8, 13.2, 2.8, 13.2, 10.2, 10.6, 10.2], false, false)
            break
        case "trim":
            ctx.beginPath()
            ctx.arc(4.6, 12, 2.1, 0, Math.PI * 2)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(11.4, 12, 2.1, 0, Math.PI * 2)
            ctx.stroke()
            line(5.8, 10.3, 11.2, 2.6)
            line(10.2, 10.3, 4.8, 2.6)
            break
        case "open":
            poly([9.2, 2.6, 13.4, 2.6, 13.4, 6.8], false, false)
            line(13.4, 2.6, 7.8, 8.2)
            poly([11, 9.6, 11, 13.4, 2.6, 13.4, 2.6, 5, 6.4, 5], false, false)
            break
        case "copy":
            roundRect(5.6, 1.8, 8.6, 8.6, 1.6, false)
            poly([10.4, 5.6, 10.4, 14.2, 1.8, 14.2, 1.8, 5.6, 5.6, 5.6], false, false)
            break
        case "library":
            line(6, 4.4, 14, 4.4)
            line(6, 8, 14, 8)
            line(6, 11.6, 14, 11.6)
            ctx.beginPath()
            ctx.arc(2.8, 4.4, 1.1, 0, Math.PI * 2)
            ctx.arc(2.8, 8, 1.1, 0, Math.PI * 2)
            ctx.arc(2.8, 11.6, 1.1, 0, Math.PI * 2)
            ctx.fill()
            break
        case "alert":
            ctx.beginPath()
            ctx.arc(8, 8, 6.2, 0, Math.PI * 2)
            ctx.stroke()
            line(8, 4.4, 8, 8.8)
            ctx.beginPath()
            ctx.arc(8, 11.4, 0.9, 0, Math.PI * 2)
            ctx.fill()
            break
        case "check":
            poly([3.6, 8.4, 6.6, 11.4, 12.4, 4.6], false, false)
            break
        case "clock":
            ctx.beginPath()
            ctx.arc(8, 8, 6.2, 0, Math.PI * 2)
            ctx.stroke()
            poly([8, 4.4, 8, 8.2, 10.8, 9.8], false, false)
            break
        case "plus":
            line(8, 3.6, 8, 12.4)
            line(3.6, 8, 12.4, 8)
            break
        case "headphones":
            arc(8, 8.6, 5.6, Math.PI, Math.PI * 2)
            roundRect(1.6, 8.4, 3, 5.4, 1.4, false)
            roundRect(11.4, 8.4, 3, 5.4, 1.4, false)
            break
        }
    }
}
