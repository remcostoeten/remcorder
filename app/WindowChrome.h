#pragma once

#include <QHash>
#include <QMargins>
#include <QMetaObject>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QQuickWindow>
#include <QtQml/qqmlregistration.h>

/**
 * Bridges the frameless window chrome in QML to the compositor.
 *
 * QWindow::startSystemMove()/startSystemResize() are not exposed to QML, and on
 * Wayland a client cannot position itself, so dragging must be delegated to the
 * compositor instead of assigning window x/y.
 *
 * Wayland also ignores Qt::WindowStaysOnTopHint, so floating overlays such as
 * the recording pill are turned into wlr-layer-shell surfaces with pinAbove():
 * the compositor keeps them above every other window (including fullscreen
 * ones) and places them by anchors plus margins. Layer surfaces cannot be moved
 * by the compositor's interactive move, so startMove() drags them by rewriting
 * the margins from pointer motion instead.
 */
class WindowChrome : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Available through the windowChrome context property")

public:
    enum Anchor {
        AnchorTop = 1,
        AnchorBottom = 2,
        AnchorLeft = 4,
        AnchorRight = 8,
    };
    Q_ENUM(Anchor)

    using QObject::QObject;

    /**
     * Makes the window a layer-shell overlay surface anchored to the given
     * screen edges with the given margins. Must be called before the window is
     * first shown. Returns false when layer-shell is unavailable (X11, or built
     * without LayerShellQt), in which case Qt::WindowStaysOnTopHint still applies.
     */
    Q_INVOKABLE bool pinAbove(QQuickWindow *window, int anchors, int left, int top, int right, int bottom);

    /** Repositions a pinned window; no-op for windows that are not pinned. */
    Q_INVOKABLE void moveOverlay(QQuickWindow *window, int left, int top, int right, int bottom);

    Q_INVOKABLE bool isPinned(QQuickWindow *window) const;

    Q_INVOKABLE void startMove(QQuickWindow *window);

    Q_INVOKABLE void startResize(QQuickWindow *window, int edges);

    /**
     * Limits pointer input to the given rectangles (each a Qt.rect) so
     * transparent padding lets clicks through to whatever is underneath.
     *
     * On X11 the same mask also clips what is painted, so anything that must
     * stay visible (such as the keystroke strip above the recording pill) has
     * to be part of the region.
     */
    Q_INVOKABLE void setInputRects(QQuickWindow *window, const QVariantList &rects);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    struct Pinned {
        int anchors = 0;
        QMargins margins;
    };

    struct Drag {
        QPointer<QQuickWindow> window;
        QPointF anchor;
        bool anchored = false;
        bool awaitingFrame = false;
        QMetaObject::Connection frameSwapped;
    };

    void applyMargins(QQuickWindow *window, const Pinned &pinned);
    void dragTo(const QPointF &position);
    void endDrag();

    QHash<QQuickWindow *, Pinned> m_pinned;
    Drag m_drag;
};
