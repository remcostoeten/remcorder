#pragma once

#include <QElapsedTimer>
#include <QQuickPaintedItem>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

class AnnotationCanvas : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool hasStrokes READ hasStrokes NOTIFY hasStrokesChanged)

public:
    explicit AnnotationCanvas(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;
    bool hasStrokes() const { return !m_strokes.isEmpty(); }
    Q_INVOKABLE void begin(qreal x, qreal y, QColor color, qreal width, int seconds, bool reduceMotion);
    Q_INVOKABLE void append(qreal x, qreal y);
    Q_INVOKABLE void finish();
    Q_INVOKABLE void clear();

signals:
    void hasStrokesChanged();

private:
    struct Stroke {
        QList<QPointF> points;
        QList<qreal> distances;
        QColor color;
        qreal width;
        int hold;
        bool reduceMotion;
        qint64 finished = -1;
    };
    void tick();
    void addPoint(Stroke &stroke, QPointF point);
    QList<Stroke> m_strokes;
    QTimer m_timer;
    QElapsedTimer m_clock;
    QPointF m_lastInput;
    bool m_drawing = false;
};
