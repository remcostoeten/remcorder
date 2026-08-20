#include "Branding.h"
#include "RecorderBackend.h"
#include "WindowChrome.h"

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
    QGuiApplication::setWindowIcon(branding::applicationIcon());
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    RecorderBackend backend;
    WindowChrome windowChrome;
    app.setQuitOnLastWindowClosed(!backend.trayAvailable());

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("windowChrome"), &windowChrome);
    engine.loadFromModule(QStringLiteral("Remcorder"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
