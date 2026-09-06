#include "SingleInstance.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QStandardPaths>

namespace {
constexpr int kHandshakeTimeoutMs = 400;
}

SingleInstance::SingleInstance(QObject *parent)
    : QObject(parent)
{
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    connect(&m_server, &QLocalServer::newConnection, this, &SingleInstance::acceptConnection);
}

QString SingleInstance::socketName()
{
    const QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtimeDir.isEmpty())
        return QStringLiteral("remcorder-launcher");
    return runtimeDir + QStringLiteral("/remcorder-launcher.sock");
}

bool SingleInstance::forwardToRunningInstance(const QStringList &arguments)
{
    QLocalSocket socket;
    socket.connectToServer(socketName());
    if (!socket.waitForConnected(kHandshakeTimeoutMs))
        return false;

    QJsonObject message{{QStringLiteral("action"), QStringLiteral("show")}};
    const qsizetype trimIndex = arguments.indexOf(QStringLiteral("--trim"));
    if (trimIndex >= 0 && trimIndex + 1 < arguments.size()) {
        message[QStringLiteral("action")] = QStringLiteral("trim");
        message[QStringLiteral("path")] = QFileInfo(arguments.at(trimIndex + 1)).absoluteFilePath();
    } else if (arguments.contains(QStringLiteral("--tray"))) {
        message[QStringLiteral("action")] = QStringLiteral("noop");
    }

    socket.write(QJsonDocument(message).toJson(QJsonDocument::Compact));
    socket.write("\n");
    socket.flush();
    socket.waitForBytesWritten(kHandshakeTimeoutMs);
    socket.disconnectFromServer();
    return true;
}

bool SingleInstance::claim()
{
    // A stale socket file survives crashes; connecting already failed, so it is safe to remove.
    QLocalServer::removeServer(socketName());
    return m_server.listen(socketName());
}

void SingleInstance::acceptConnection()
{
    while (QLocalSocket *client = m_server.nextPendingConnection()) {
        connect(client, &QLocalSocket::readyRead, this, [this, client] {
            if (!client->canReadLine())
                return;
            handleMessage(client->readLine().trimmed());
            client->disconnectFromServer();
        });
        connect(client, &QLocalSocket::disconnected, client, &QObject::deleteLater);
    }
}

void SingleInstance::handleMessage(const QByteArray &message)
{
    const QJsonObject payload = QJsonDocument::fromJson(message).object();
    const QString action = payload.value(QStringLiteral("action")).toString();
    if (action == QLatin1String("trim")) {
        const QString path = payload.value(QStringLiteral("path")).toString();
        if (!path.isEmpty()) {
            emit trimRequested(path);
            return;
        }
    }
    if (action != QLatin1String("noop"))
        emit showRequested();
}
