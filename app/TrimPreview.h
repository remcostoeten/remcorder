#pragma once

#include <QElapsedTimer>
#include <QImage>
#include <QMutex>
#include <QObject>
#include <QQuickImageProvider>
#include <QVideoSink>

class TrimPreview final : public QQuickImageProvider
{
    Q_OBJECT

    Q_PROPERTY(QVideoSink *videoSink READ videoSink CONSTANT)
    Q_PROPERTY(bool available READ available NOTIFY frameChanged)
    Q_PROPERTY(quint64 revision READ revision NOTIFY frameChanged)

public:
    TrimPreview();

    QVideoSink *videoSink() { return &m_videoSink; }
    bool available() const;
    quint64 revision() const { return m_revision; }
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

    Q_INVOKABLE void clear();

signals:
    void frameChanged();

private slots:
    void updateFrame(const QVideoFrame &frame);

private:
    mutable QMutex m_mutex;
    QVideoSink m_videoSink;
    QImage m_image;
    QElapsedTimer m_frameTimer;
    quint64 m_revision = 0;
};
