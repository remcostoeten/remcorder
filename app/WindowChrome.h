#pragma once

#include <QObject>
#include <QQuickWindow>

/**
 * Bridges the frameless window chrome in QML to the compositor.
 *
 * QWindow::startSystemMove()/startSystemResize() are not exposed to QML, and on
 * Wayland a client cannot position itself, so dragging must be delegated to the
 * compositor instead of assigning window x/y.
 */
class WindowChrome final : public QObject
{
    Q_OBJECT

public:
    using QObject::QObject;

    Q_INVOKABLE void startMove(QQuickWindow *window)
    {
        if (window)
            window->startSystemMove();
    }

    Q_INVOKABLE void startResize(QQuickWindow *window, int edges)
    {
        if (window)
            window->startSystemResize(Qt::Edges(edges));
    }
};
