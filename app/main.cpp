#include "RecorderBackend.h"

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QSystemTrayIcon>

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("Remcorder"));
    QCoreApplication::setOrganizationName(QStringLiteral("RemcoStoeten"));
    QGuiApplication::setDesktopFileName(QStringLiteral("remcorder"));
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    RecorderBackend backend;
    app.setQuitOnLastWindowClosed(!backend.trayAvailable());

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.loadFromModule(QStringLiteral("Remcorder"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
