#include "AnnotationCanvas.h"
#include "AnnotationInput.h"
#include "WindowChrome.h"

#include <QImage>
#include <QPainter>
#include <QSignalSpy>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QSettings>
#include <QTemporaryDir>
#include <QtTest>

QQuickItem *findVisualItem(QQuickItem *root, const QString &name)
{
    if (root->objectName() == name)
        return root;
    for (auto *child : root->childItems()) {
        if (auto *found = findVisualItem(child, name))
            return found;
    }
    return nullptr;
}

class TestInput : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active MEMBER active NOTIFY activeChanged)
    Q_PROPERTY(bool enabled MEMBER enabled)
public:
    bool active = false;
    bool enabled = false;
signals:
    void activeChanged();
    void clearRequested();
};

class AnnotationTests : public QObject
{
    Q_OBJECT
    QTemporaryDir m_settings;

private slots:
    void initTestCase()
    {
        QCoreApplication::setOrganizationName("RemcorderTests");
        QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, m_settings.path());
    }

    void overlayGestures()
    {
        TestInput input;
        WindowChrome chrome;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("annotationInput", &input);
        engine.rootContext()->setContextProperty("windowChrome", &chrome);
        QQmlComponent component(&engine);
        component.loadFromModule("AnnotationTests", "AnnotationTools");
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> tools(component.create());
        QVERIFY2(tools != nullptr, qPrintable(component.errorString()));
        input.active = true;
        emit input.activeChanged();
        QQuickWindow *window = nullptr;
        for (auto *candidate : QGuiApplication::allWindows()) {
            if (candidate->title() == "Remcorder Annotations")
                window = qobject_cast<QQuickWindow *>(candidate);
        }
        QVERIFY(window);
        auto *modeLabel = window->findChild<QQuickItem *>("annotationModeLabel");
        QVERIFY(modeLabel);
        QVERIFY(modeLabel->isVisible());
        QTRY_VERIFY(window->isVisible());
        QVERIFY(QTest::qWaitForWindowExposed(window));
        auto *canvas = window->findChild<AnnotationCanvas *>();
        auto *palette = window->findChild<QQuickItem *>("annotationPalette");
        QVERIFY(canvas);
        QVERIFY(palette);
        auto *preferences = tools->findChild<QObject *>("annotationPreferences");
        QVERIFY(preferences);
        const qreal originalWidth = preferences->property("penWidth").toReal();
        QTest::mousePress(window, Qt::LeftButton, Qt::ShiftModifier, QPoint(20, 20));
        QTest::mouseMove(window, QPoint(120, 20));
        QTest::mouseRelease(window, Qt::LeftButton, Qt::ShiftModifier, QPoint(120, 20));
        QVERIFY(canvas->hasStrokes());
        QTest::mouseClick(window, Qt::RightButton, Qt::ShiftModifier, QPoint(200, 200));
        QVERIFY(!palette->isVisible());
        QTest::mouseClick(window, Qt::RightButton, Qt::ShiftModifier, QPoint(200, 200));
        QVERIFY(palette->isVisible());
        QTest::qWait(30);
        const QPointF position = palette->position() + QPointF(30, 85);
        QWheelEvent wheel(position, position, QPoint(), QPoint(0, 120), Qt::NoButton,
                          Qt::ShiftModifier, Qt::NoScrollPhase, false);
        QCoreApplication::sendEvent(window, &wheel);
        QCOMPARE(preferences->property("penWidth").toReal(), originalWidth + 1);
        auto *swatch = findVisualItem(window->contentItem(), "penColor#5EA8FF");
        QVERIFY(swatch);
        QSignalSpy clicked(swatch, SIGNAL(clicked()));
        QTest::mouseClick(window, Qt::LeftButton, Qt::ShiftModifier,
                          swatch->mapToScene(QPointF(swatch->width() / 2, swatch->height() / 2)).toPoint());
        QCOMPARE(clicked.count(), 1);
        QVERIFY(!palette->isVisible());
        QCOMPARE(preferences->property("penColor").value<QColor>(), QColor("#5EA8FF"));
        input.active = false;
        emit input.activeChanged();
        QVERIFY(window->flags() & Qt::WindowTransparentForInput);
        QVERIFY(canvas->hasStrokes());
        emit input.clearRequested();
        QVERIFY(!canvas->hasStrokes());
        QVERIFY(!window->isVisible());
    }

    void shiftHoldDoesNotActivate()
    {
        AnnotationInput input;
        input.observeShift(true, false);
        QTest::qWait(1020);
        input.observeShift(true, false);
        QVERIFY(!input.active());
        input.observeShift(false, false);
        QVERIFY(!input.active());
    }

    void doubleTapTogglesAndPersistsAfterRelease()
    {
        AnnotationInput input;
        QSignalSpy clear(&input, &AnnotationInput::clearRequested);
        input.observeShift(true, false);
        input.observeShift(false, false);
        QVERIFY(!input.active());
        input.observeShift(true, false);
        input.observeShift(false, false);
        QVERIFY(input.active());
        input.observeShift(false, false);
        QVERIFY(input.active());
        input.observeShift(true, false);
        input.observeShift(false, false);
        QVERIFY(input.active());
        input.observeShift(true, false);
        input.observeShift(false, false);
        QVERIFY(!input.active());
        QCOMPARE(clear.count(), 0);
    }

    void anotherKeyExitsDrawingMode()
    {
        AnnotationInput input;
        input.observeShift(true, false);
        input.observeShift(false, false);
        input.observeShift(true, false);
        input.observeShift(false, false);
        QVERIFY(input.active());
        input.observeShift(false, true);
        QVERIFY(!input.active());
    }

    void typingDoesNotClearOrActivate()
    {
        AnnotationInput input;
        QSignalSpy clear(&input, &AnnotationInput::clearRequested);
        input.observeShift(true, false);
        input.observeShift(false, false);
        input.observeShift(true, true);
        QTest::qWait(1020);
        input.observeShift(true, false);
        QVERIFY(!input.active());
        input.observeShift(false, false);
        QCOMPARE(clear.count(), 0);
    }

    void slowTapsDoNotActivate()
    {
        AnnotationInput input;
        QSignalSpy clear(&input, &AnnotationInput::clearRequested);
        input.observeShift(true, false);
        input.observeShift(false, false);
        QTest::qWait(370);
        input.observeShift(true, false);
        input.observeShift(false, false);
        QCOMPARE(clear.count(), 0);
        QVERIFY(!input.active());
    }

    void unfinishedStrokeDoesNotExpire()
    {
        AnnotationCanvas canvas;
        canvas.begin(10, 20, Qt::red, 4, 1, false);
        QTest::qWait(1300);
        QVERIFY(canvas.hasStrokes());
        canvas.clear();
        QVERIFY(!canvas.hasStrokes());
        canvas.append(20, 20);
        canvas.finish();
        QVERIFY(!canvas.hasStrokes());
    }

    void expiresFromStartToEnd()
    {
        AnnotationCanvas canvas;
        canvas.begin(10, 20, Qt::red, 4, 1, false);
        canvas.append(110, 20);
        canvas.finish();
        QTest::qWait(1120);
        QImage image(130, 40, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);
        QPainter painter(&image);
        canvas.paint(&painter);
        painter.end();
        QCOMPARE(image.pixelColor(15, 20).alpha(), 0);
        QVERIFY(image.pixelColor(105, 20).alpha() > 200);
        QTest::qWait(160);
        QVERIFY(!canvas.hasStrokes());
    }

    void reducedMotionFadesWholeStroke()
    {
        AnnotationCanvas canvas;
        canvas.begin(10, 20, Qt::red, 4, 1, true);
        canvas.append(110, 20);
        canvas.finish();
        QTest::qWait(1120);
        QImage image(130, 40, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);
        QPainter painter(&image);
        canvas.paint(&painter);
        painter.end();
        const int start = image.pixelColor(15, 20).alpha();
        QVERIFY(start > 0 && start < 255);
        QCOMPARE(start, image.pixelColor(105, 20).alpha());
    }

    void strokesHaveIndependentLifetimes()
    {
        AnnotationCanvas canvas;
        canvas.begin(10, 20, Qt::red, 4, 1, false);
        canvas.finish();
        canvas.begin(30, 20, Qt::blue, 8, 3, false);
        canvas.finish();
        QTest::qWait(1300);
        QVERIFY(canvas.hasStrokes());
        QImage image(50, 40, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);
        QPainter painter(&image);
        canvas.paint(&painter);
        painter.end();
        QCOMPARE(image.pixelColor(10, 20).alpha(), 0);
        QCOMPARE(image.pixelColor(30, 20), QColor(Qt::blue));
    }
};

QTEST_MAIN(AnnotationTests)
#include "annotations.moc"
