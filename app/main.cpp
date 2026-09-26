#include "Branding.h"
#include "AnnotationInput.h"
#include "RecorderBackend.h"
#include "SingleInstance.h"
#include "TrimPreview.h"
#include "WindowChrome.h"

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QShortcut>
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

    SingleInstance singleInstance;
    if (singleInstance.forwardToRunningInstance(app.arguments()))
        return 0;
    singleInstance.claim();

    RecorderBackend backend;
    WindowChrome windowChrome;
    AnnotationInput annotationInput;
    // The launcher hides itself while the floating recording pill is up, so Qt
    // must not treat that as the last window closing. Main.qml quits explicitly
    // when there is no tray to fall back to.
    app.setQuitOnLastWindowClosed(false);

    auto *quitShortcut = new QShortcut(QKeySequence::Quit, &app);
    quitShortcut->setContext(Qt::ApplicationShortcut);
    QObject::connect(quitShortcut, &QShortcut::activated, &app, &QCoreApplication::quit);

    QQmlApplicationEngine engine;
    auto *trimPreview = new TrimPreview;
    auto *savedPreview = new TrimPreview;
    auto *blurPreview = new TrimPreview;
    engine.addImageProvider(QStringLiteral("trimPreview"), trimPreview);
    engine.addImageProvider(QStringLiteral("savedPreview"), savedPreview);
    engine.addImageProvider(QStringLiteral("blurPreview"), blurPreview);
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("trimPreview"), trimPreview);
    engine.rootContext()->setContextProperty(QStringLiteral("savedPreview"), savedPreview);
    engine.rootContext()->setContextProperty(QStringLiteral("blurPreview"), blurPreview);
    engine.rootContext()->setContextProperty(QStringLiteral("windowChrome"), &windowChrome);
    engine.rootContext()->setContextProperty(QStringLiteral("annotationInput"), &annotationInput);
    engine.rootContext()->setContextProperty(QStringLiteral("singleInstance"), &singleInstance);
    engine.loadFromModule(QStringLiteral("Remcorder"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
