#include "WindowChrome.h"

#include <QEvent>
#include <QGuiApplication>
#include <QMouseEvent>
#include <QRectF>
#include <QRegion>
#include <QVariant>

#ifdef REMCORDER_HAVE_LAYERSHELLQT
#include <LayerShellQt/Window>
#endif

namespace {

bool layerShellAvailable()
{
#ifdef REMCORDER_HAVE_LAYERSHELLQT
    return QGuiApplication::platformName() == QLatin1String("wayland");
#else
    return false;
#endif
}

#ifdef REMCORDER_HAVE_LAYERSHELLQT
LayerShellQt::Window::Anchors toLayerAnchors(int anchors)
{
    LayerShellQt::Window::Anchors result;
    if (anchors & WindowChrome::AnchorTop)
        result |= LayerShellQt::Window::AnchorTop;
    if (anchors & WindowChrome::AnchorBottom)
        result |= LayerShellQt::Window::AnchorBottom;
    if (anchors & WindowChrome::AnchorLeft)
        result |= LayerShellQt::Window::AnchorLeft;
    if (anchors & WindowChrome::AnchorRight)
        result |= LayerShellQt::Window::AnchorRight;
    return result;
}
#endif

}

bool WindowChrome::pinAbove(QQuickWindow *window, int anchors, int left, int top, int right, int bottom)
{
    if (!window || !layerShellAvailable())
        return false;

#ifdef REMCORDER_HAVE_LAYERSHELLQT
    Pinned pinned;
    pinned.anchors = anchors;
    pinned.margins = QMargins(left, top, right, bottom);

    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerOverlay);
    layer->setAnchors(toLayerAnchors(anchors));
    layer->setMargins(pinned.margins);
    layer->setExclusiveZone(0);
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
#ifdef REMCORDER_LAYERSHELL_HAS_ACTIVATE_ON_SHOW
    layer->setActivateOnShow(false);
#endif
    layer->setScope(QStringLiteral("remcorder-overlay"));

    m_pinned.insert(window, pinned);
    connect(window, &QObject::destroyed, this, [this, window] {
        m_pinned.remove(window);
    });
    return true;
#else
    Q_UNUSED(anchors)
    Q_UNUSED(left)
    Q_UNUSED(top)
    Q_UNUSED(right)
    Q_UNUSED(bottom)
    return false;
#endif
}

void WindowChrome::moveOverlay(QQuickWindow *window, int left, int top, int right, int bottom)
{
    auto it = m_pinned.find(window);
    if (it == m_pinned.end())
        return;
    it->margins = QMargins(left, top, right, bottom);
    applyMargins(window, *it);
}

bool WindowChrome::isPinned(QQuickWindow *window) const
{
    return m_pinned.contains(window);
}

void WindowChrome::applyMargins(QQuickWindow *window, const Pinned &pinned)
{
#ifdef REMCORDER_HAVE_LAYERSHELLQT
    LayerShellQt::Window::get(window)->setMargins(pinned.margins);
    // set_margin only takes effect on the next surface commit, and an idle
    // window (paused recording, no animation) would otherwise never commit.
    // requestUpdate() is not enough: the threaded render loop skips the frame
    // when nothing in the scene changed, so force a repaint.
    window->update();
#else
    Q_UNUSED(window)
    Q_UNUSED(pinned)
#endif
}

void WindowChrome::startMove(QQuickWindow *window)
{
    if (!window)
        return;

    if (!m_pinned.contains(window)) {
        window->startSystemMove();
        return;
    }

    endDrag();
    m_drag.window = window;
    m_drag.anchored = false;
    m_drag.awaitingFrame = false;
    // frameSwapped fires on the render thread, so queue it back to this one.
    m_drag.frameSwapped = connect(window, &QQuickWindow::frameSwapped, this, [this] {
        m_drag.awaitingFrame = false;
    }, Qt::QueuedConnection);
    window->installEventFilter(this);
}

bool WindowChrome::eventFilter(QObject *watched, QEvent *event)
{
    if (!m_drag.window || watched != m_drag.window)
        return false;

    switch (event->type()) {
    case QEvent::MouseMove:
        dragTo(static_cast<QMouseEvent *>(event)->position());
        break;
    case QEvent::MouseButtonRelease:
    case QEvent::Hide:
    case QEvent::TouchCancel:
        endDrag();
        break;
    default:
        break;
    }
    return false;
}

void WindowChrome::dragTo(const QPointF &position)
{
    if (!m_drag.anchored) {
        m_drag.anchor = position;
        m_drag.anchored = true;
        return;
    }
    // The surface moves underneath the pointer, so once the compositor has
    // applied a margin change the pointer reads as sitting on the anchor again.
    // Motion that arrives before that commit lands would be counted twice, so
    // only one margin update is issued per rendered frame.
    if (m_drag.awaitingFrame)
        return;

    const QPointF delta = position - m_drag.anchor;
    const int dx = qRound(delta.x());
    const int dy = qRound(delta.y());
    if (dx == 0 && dy == 0)
        return;

    auto it = m_pinned.find(m_drag.window);
    if (it == m_pinned.end()) {
        endDrag();
        return;
    }

    QMargins margins = it->margins;
    if (it->anchors & AnchorLeft)
        margins.setLeft(qMax(0, margins.left() + dx));
    else if (it->anchors & AnchorRight)
        margins.setRight(qMax(0, margins.right() - dx));
    if (it->anchors & AnchorTop)
        margins.setTop(qMax(0, margins.top() + dy));
    else if (it->anchors & AnchorBottom)
        margins.setBottom(qMax(0, margins.bottom() - dy));

    if (margins == it->margins)
        return;
    it->margins = margins;
    m_drag.awaitingFrame = true;
    applyMargins(m_drag.window, *it);
}

void WindowChrome::endDrag()
{
    if (m_drag.window) {
        m_drag.window->removeEventFilter(this);
        disconnect(m_drag.frameSwapped);
    }
    m_drag = Drag();
}

void WindowChrome::startResize(QQuickWindow *window, int edges)
{
    if (window)
        window->startSystemResize(Qt::Edges(edges));
}

void WindowChrome::setInputRects(QQuickWindow *window, const QVariantList &rects)
{
    if (!window)
        return;
    QRegion region;
    for (const QVariant &value : rects)
        region += value.toRectF().toAlignedRect();
    window->setMask(region);
}
