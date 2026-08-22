#include "TrimPreview.h"

#include <QMutexLocker>
#include <QVideoFrame>

TrimPreview::TrimPreview()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
    connect(&m_videoSink, &QVideoSink::videoFrameChanged,
            this, &TrimPreview::updateFrame);
}

bool TrimPreview::available() const
{
    const QMutexLocker locker(&m_mutex);
    return !m_image.isNull();
}

QImage TrimPreview::requestImage(const QString &, QSize *size, const QSize &requestedSize)
{
    QImage image;
    {
        const QMutexLocker locker(&m_mutex);
        image = m_image;
    }

    if (size)
        *size = image.size();
    if (requestedSize.isValid())
        return image.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    return image;
}

void TrimPreview::clear()
{
    {
        const QMutexLocker locker(&m_mutex);
        m_image = {};
    }
    ++m_revision;
    m_frameTimer.invalidate();
    emit frameChanged();
}

void TrimPreview::updateFrame(const QVideoFrame &frame)
{
    if (m_frameTimer.isValid() && m_frameTimer.elapsed() < 30)
        return;

    QImage image = frame.toImage();
    if (image.isNull())
        return;

    image = image.scaled(QSize(960, 540), Qt::KeepAspectRatio, Qt::FastTransformation);
    {
        const QMutexLocker locker(&m_mutex);
        m_image = std::move(image);
    }
    ++m_revision;
    m_frameTimer.restart();
    emit frameChanged();
}
