#include "AnnotationCanvas.h"

#include <QLineF>
#include <QPainter>
#include <QPainterPath>
#include <algorithm>

AnnotationCanvas::AnnotationCanvas(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    m_clock.start();
    m_timer.setInterval(16);
    m_timer.setTimerType(Qt::PreciseTimer);
    connect(&m_timer, &QTimer::timeout, this, &AnnotationCanvas::tick);
}

void AnnotationCanvas::begin(qreal x, qreal y, QColor color, qreal width, int seconds, bool reduceMotion)
{
    finish();
    if (m_strokes.size() >= 256)
        m_strokes.removeFirst();
    m_strokes.append(Stroke{{QPointF(x, y)}, {0}, color, qBound(1.0, width, 40.0),
                            qBound(1, seconds, 300) * 1000, reduceMotion});
    m_lastInput = QPointF(x, y);
    m_drawing = true;
    m_timer.start();
    emit hasStrokesChanged();
    update();
}

void AnnotationCanvas::addPoint(Stroke &stroke, QPointF point)
{
    const qreal distance = QLineF(stroke.points.last(), point).length();
    if (distance < 0.1)
        return;
    stroke.distances.append(stroke.distances.last() + distance);
    stroke.points.append(point);
}

void AnnotationCanvas::append(qreal x, qreal y)
{
    if (!m_drawing)
        return;
    auto &stroke = m_strokes.last();
    const QPointF input(x, y);
    if (QLineF(m_lastInput, input).length() < 0.5)
        return;
    const QPointF start = stroke.points.last();
    const QPointF end = (m_lastInput + input) / 2;
    const int steps = qBound(1, qCeil((QLineF(start, m_lastInput).length()
                                    + QLineF(m_lastInput, end).length()) / 2), 128);
    for (int i = 1; i <= steps; ++i) {
        const qreal t = qreal(i) / steps;
        addPoint(stroke, (1 - t) * (1 - t) * start + 2 * (1 - t) * t * m_lastInput + t * t * end);
    }
    m_lastInput = input;
    if (stroke.points.size() >= 65536) {
        const QColor color = stroke.color;
        const qreal width = stroke.width;
        const int seconds = stroke.hold / 1000;
        const bool reduced = stroke.reduceMotion;
        begin(x, y, color, width, seconds, reduced);
    }
    update();
}

void AnnotationCanvas::finish()
{
    if (!m_drawing)
        return;
    addPoint(m_strokes.last(), m_lastInput);
    m_strokes.last().finished = m_clock.elapsed();
    m_drawing = false;
    update();
}

void AnnotationCanvas::clear()
{
    m_strokes.clear();
    m_drawing = false;
    m_timer.stop();
    emit hasStrokesChanged();
    update();
}

void AnnotationCanvas::tick()
{
    const qint64 now = m_clock.elapsed();
    bool expiring = false;
    m_strokes.removeIf([now, &expiring](const Stroke &stroke) {
        if (stroke.finished < 0)
            return false;
        const qint64 age = now - stroke.finished - stroke.hold;
        expiring |= age >= 0;
        return age >= 250;
    });
    if (m_strokes.isEmpty()) {
        m_timer.stop();
        emit hasStrokesChanged();
    }
    if (expiring)
        update();
}

void AnnotationCanvas::paint(QPainter *painter)
{
    painter->setRenderHint(QPainter::Antialiasing);
    const qint64 now = m_clock.elapsed();
    for (const auto &stroke : std::as_const(m_strokes)) {
        const qreal progress = stroke.finished < 0 ? 0.0
            : qBound(0.0, qreal(now - stroke.finished - stroke.hold) / 250.0, 1.0);
        if (progress >= 1)
            continue;
        painter->setOpacity(stroke.reduceMotion || stroke.points.size() == 1 ? 1 - progress : 1);
        painter->setPen(QPen(stroke.color, stroke.width, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        if (stroke.points.size() == 1) {
            painter->drawPoint(stroke.points.first());
            continue;
        }
        const qreal removed = stroke.reduceMotion ? 0 : stroke.distances.last() * progress;
        auto it = std::upper_bound(stroke.distances.cbegin(), stroke.distances.cend(), removed);
        const qsizetype index = qBound(qsizetype(1), it - stroke.distances.cbegin(), stroke.points.size() - 1);
        const qreal t = (removed - stroke.distances[index - 1])
            / (stroke.distances[index] - stroke.distances[index - 1]);
        QPainterPath path(stroke.points[index - 1] * (1 - t) + stroke.points[index] * t);
        for (qsizetype i = index; i < stroke.points.size(); ++i)
            path.lineTo(stroke.points[i]);
        if (m_drawing && &stroke == &m_strokes.last())
            path.lineTo(m_lastInput);
        painter->drawPath(path);
    }
}
