#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QTimer>
#include <QHash>

class AnnotationInput : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit AnnotationInput(QObject *parent = nullptr);
    ~AnnotationInput() override;
    bool enabled() const { return m_enabled; }
    bool active() const { return m_active; }
    QString error() const { return m_error; }
    void setEnabled(bool enabled);
    void observeShift(bool down, bool chord);

signals:
    void enabledChanged();
    void activeChanged();
    void errorChanged();
    void clearRequested();

private:
    void discover();
    void poll();
    void setActive(bool active);
    void closeDevices();
    QTimer m_poll;
    QTimer m_discovery;
    QElapsedTimer m_clock;
    QHash<QString, int> m_devices;
    bool m_enabled = false;
    bool m_active = false;
    bool m_down = false;
    bool m_chord = false;
    qint64 m_pressed = 0;
    qint64 m_lastTap = -1000;
    QString m_error;
};
