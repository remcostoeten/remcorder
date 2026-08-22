#include "Branding.h"
#include "RecorderBackend.h"
#include "TrimPreview.h"
#include "WindowChrome.h"

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QSystemTrayIcon>

int main(int argc, char *argv[])
{
    if (!qEnvironmentVariableIsSet("QT_FFMPEG_DECODING_HW_DEVICE_TYPES"))
        qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", ",");

    QApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("Remcorder"));
    QCoreApplication::setOrganizationName(QStringLiteral("RemcoStoeten"));
    QGuiApplication::setDesktopFileName(QStringLiteral("remcorder"));
    QGuiApplication::setWindowIcon(branding::applicationIcon());
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    RecorderBackend backend;
    WindowChrome windowChrome;
    // The launcher hides itself while the floating recording pill is up, so Qt
    // must not treat that as the last window closing. Main.qml quits explicitly
    // when there is no tray to fall back to.
    app.setQuitOnLastWindowClosed(false);

    QQmlApplicationEngine engine;
    auto *trimPreview = new TrimPreview;
    engine.addImageProvider(QStringLiteral("trimPreview"), trimPreview);
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("trimPreview"), trimPreview);
    engine.rootContext()->setContextProperty(QStringLiteral("windowChrome"), &windowChrome);
    engine.loadFromModule(QStringLiteral("Remcorder"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
