#pragma once

#include <QLocalServer>
#include <QObject>
#include <QString>

/**
 * Keeps a single Remcorder launcher alive per user session.
 *
 * The first process listens on a local socket; later launches hand their
 * arguments to it and exit, so the floating recording pill and tray icon
 * never appear more than once.
 */
class SingleInstance final : public QObject
{
    Q_OBJECT

public:
    explicit SingleInstance(QObject *parent = nullptr);

    /// Returns true when another launcher already owns the session socket.
    bool forwardToRunningInstance(const QStringList &arguments);

    /// Binds this process as the primary instance.
    bool claim();

signals:
    void showRequested();
    void trimRequested(const QString &path);

private:
    void acceptConnection();
    void handleMessage(const QByteArray &message);
    static QString socketName();

    QLocalServer m_server;
};
