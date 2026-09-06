#include "RecorderBackend.h"

#include "Branding.h"

#include <QAction>
#include <QApplication>
#include <QAudioDevice>
#include <QAudioSink>
#include <QAudioSource>
#include <QBuffer>
#include <QClipboard>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileDialog>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QMediaDevices>
#include <QMenu>
#include <QProcess>
#include <QRegularExpression>
#include <QScopeGuard>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <unistd.h>

#include <cmath>
#include <utility>

namespace {
constexpr auto organization = "RemcoStoeten";
constexpr auto application = "Remcorder";

QString motionBlurFilter(const QString &strength)
{
    int frames = 3;
    if (strength == QStringLiteral("subtle"))
        frames = 2;
    else if (strength == QStringLiteral("strong"))
        frames = 5;

    QStringList weights;
    for (int index = 1; index <= frames; ++index)
        weights.append(QString::number(index));
    return QStringLiteral("tmix=frames=%1:weights=%2")
        .arg(frames)
        .arg(weights.join(QLatin1Char(' ')));
}

QByteArray renderTones(const QAudioFormat &format, const QList<QPair<double, int>> &tones)
{
    const double rate = format.sampleRate();
    const double fadeFrames = qMax(1.0, rate * 0.006);
    const int channels = format.channelCount();
    const bool isFloat = format.sampleFormat() == QAudioFormat::Float;

    QByteArray data;
    for (const auto &tone : tones) {
        const double frequency = tone.first;
        const int frames = static_cast<int>(rate * tone.second / 1000.0);
        for (int frame = 0; frame < frames; ++frame) {
            double amplitude = 0.0;
            if (frequency > 0.0) {
                const double fade = std::min({1.0, frame / fadeFrames, (frames - frame) / fadeFrames});
                amplitude = 0.3 * fade * std::sin(2.0 * M_PI * frequency * frame / rate);
            }
            for (int channel = 0; channel < channels; ++channel) {
                if (isFloat) {
                    const float value = static_cast<float>(amplitude);
                    data.append(reinterpret_cast<const char *>(&value), sizeof(value));
                } else {
                    const qint16 value = static_cast<qint16>(amplitude * 32767.0);
                    data.append(reinterpret_cast<const char *>(&value), sizeof(value));
                }
            }
        }
    }
    return data;
}

QString firstValue(const QVariantList &items, const QString &fallback)
{
    if (items.isEmpty())
        return fallback;
    return items.first().toMap().value(QStringLiteral("value")).toString();
}
}

RecorderBackend::RecorderBackend(QObject *parent)
    : QObject(parent)
{
    const QStringList arguments = QCoreApplication::arguments();
    const qsizetype trimIndex = arguments.indexOf(QStringLiteral("--trim"));
    if (trimIndex >= 0 && trimIndex + 1 < arguments.size())
        m_initialTrimPath = QFileInfo(arguments.at(trimIndex + 1)).absoluteFilePath();
    m_startHidden = m_initialTrimPath.isEmpty()
        && arguments.contains(QStringLiteral("--tray"))
        && trayAvailable();

    loadSettings();
    setupTray();
    connect(this, &RecorderBackend::countdownChanged, this, &RecorderBackend::updateTray);

    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(1000);
    connect(m_pollTimer, &QTimer::timeout, this, &RecorderBackend::refreshState);
    m_pollTimer->start();

    QTimer::singleShot(0, this, [this] {
        refreshDevices();
        QJsonObject response;
        if (!request({{QStringLiteral("action"), QStringLiteral("status")}}, &response, false)) {
            startService();
        } else {
            applyResponse(response);
        }
    });
}

RecorderBackend::~RecorderBackend()
{
    if (m_clickHighlightActive)
        armClickEffect(false);
    stopMicMonitor();
    if (m_cueSink)
        m_cueSink->stop();
    if (m_trimProcess && m_trimProcess->state() != QProcess::NotRunning) {
        m_trimProcess->terminate();
        if (!m_trimProcess->waitForFinished(1500)) {
            m_trimProcess->kill();
            m_trimProcess->waitForFinished(500);
        }
    }
    if (!m_trimTemporaryFile.isEmpty())
        QFile::remove(m_trimTemporaryFile);
}

bool RecorderBackend::trayAvailable() const
{
    return QSystemTrayIcon::isSystemTrayAvailable();
}

void RecorderBackend::setCaptureSource(const QString &value)
{
    if (value.isEmpty() || value == m_captureSource)
        return;
    m_captureSource = value;
    saveSetting(QStringLiteral("captureSource"), value);
    if (m_choosingSource || m_selectionReady)
        abandonCaptureSelection();
    emit settingsChanged();
}

QString RecorderBackend::captureRegionLabel() const
{
    if (m_captureRegion.isEmpty())
        return QStringLiteral("No region selected");

    QStringList parts = m_captureRegion.split(QLatin1Char('+'));
    if (parts.size() != 3)
        return m_captureRegion;
    return QStringLiteral("%1 px at %2, %3")
        .arg(parts[0].replace(QLatin1Char('x'), QStringLiteral(" × ")),
             parts.at(1),
             parts.at(2));
}

void RecorderBackend::setCaptureRegionFromRect(qreal x,
                                               qreal y,
                                               qreal width,
                                               qreal height,
                                               qreal devicePixelRatio)
{
    // Wayland compositors hand out logical coordinates, X11 hands out device pixels,
    // and gpu-screen-recorder speaks whichever the session uses.
    const qreal scale = QGuiApplication::platformName().contains(QStringLiteral("wayland"))
        ? 1.0
        : (devicePixelRatio > 0 ? devicePixelRatio : 1.0);

    const int scaledWidth = qRound(width * scale);
    const int scaledHeight = qRound(height * scale);
    if (scaledWidth < 16 || scaledHeight < 16) {
        setError(QStringLiteral("That region is too small; drag a larger area."));
        return;
    }

    const QString region = QStringLiteral("%1x%2+%3+%4")
        .arg(scaledWidth)
        .arg(scaledHeight)
        .arg(qRound(x * scale))
        .arg(qRound(y * scale));
    if (region == m_captureRegion && m_captureSource == QStringLiteral("region"))
        return;

    m_captureRegion = region;
    m_captureSource = QStringLiteral("region");
    saveSetting(QStringLiteral("captureRegion"), region);
    saveSetting(QStringLiteral("captureSource"), m_captureSource);
    setError({});
    emit settingsChanged();
}

void RecorderBackend::clearCaptureRegion()
{
    if (m_captureRegion.isEmpty())
        return;
    m_captureRegion.clear();
    saveSetting(QStringLiteral("captureRegion"), m_captureRegion);
    emit settingsChanged();
}

void RecorderBackend::setDesktopAudioEnabled(bool value)
{
    if (value == m_desktopAudioEnabled)
        return;
    m_desktopAudioEnabled = value;
    saveSetting(QStringLiteral("desktopAudioEnabled"), value);
    emit settingsChanged();
}

void RecorderBackend::setMicrophoneEnabled(bool value)
{
    if (value == m_microphoneEnabled)
        return;
    m_microphoneEnabled = value;
    saveSetting(QStringLiteral("microphoneEnabled"), value);
    emit settingsChanged();
    syncMicMonitor();
}

void RecorderBackend::setOutputDevice(const QString &value)
{
    if (value.isEmpty() || value == m_outputDevice)
        return;
    m_outputDevice = value;
    saveSetting(QStringLiteral("outputDevice"), value);
    emit settingsChanged();
}

void RecorderBackend::setInputDevice(const QString &value)
{
    if (value.isEmpty() || value == m_inputDevice)
        return;
    m_inputDevice = value;
    saveSetting(QStringLiteral("inputDevice"), value);
    emit settingsChanged();
    if (micMonitorActive()) {
        stopMicMonitor();
        startMicMonitor();
    }
    loadMicGain();
}

void RecorderBackend::setQualityPreset(const QString &value)
{
    if (value.isEmpty() || value == m_qualityPreset)
        return;
    m_qualityPreset = value;
    saveSetting(QStringLiteral("qualityPreset"), value);
    emit settingsChanged();
}

void RecorderBackend::setOutputDirectory(const QString &value)
{
    const QString clean = QDir::cleanPath(value);
    if (clean.isEmpty() || clean == m_outputDirectory)
        return;
    m_outputDirectory = clean;
    saveSetting(QStringLiteral("outputDirectory"), clean);
    emit settingsChanged();
}

void RecorderBackend::setCaptureCursor(bool value)
{
    if (value == m_captureCursor)
        return;
    m_captureCursor = value;
    saveSetting(QStringLiteral("captureCursor"), value);
    emit settingsChanged();
}

void RecorderBackend::setSoundCuesEnabled(bool value)
{
    if (value == m_soundCuesEnabled)
        return;
    m_soundCuesEnabled = value;
    saveSetting(QStringLiteral("soundCuesEnabled"), value);
    if (value)
        playCue({{880.0, 70}});
    emit settingsChanged();
}

void RecorderBackend::setShowKeystrokes(bool value)
{
    if (value == m_showKeystrokes)
        return;
    m_showKeystrokes = value;
    saveSetting(QStringLiteral("showKeystrokes"), value);
    if (!value)
        clearKeystrokes();
    syncKeystrokePolling();
    pushKeystrokeOptions();
    updateTray();
    emit settingsChanged();
}

void RecorderBackend::setKeystrokePlacement(const QString &value)
{
    const QString clean = value == QStringLiteral("floating")
        ? QStringLiteral("floating")
        : QStringLiteral("pill");
    if (clean == m_keystrokePlacement)
        return;
    m_keystrokePlacement = clean;
    saveSetting(QStringLiteral("keystrokePlacement"), clean);
    emit settingsChanged();
}

namespace {

QString oneOf(const QString &value, const QStringList &allowed, const QString &fallback)
{
    return allowed.contains(value) ? value : fallback;
}

}

namespace {

constexpr auto kwinService = "org.kde.KWin";
constexpr auto effectsPath = "/Effects";
constexpr auto effectsInterface = "org.kde.kwin.Effects";
constexpr auto clickEffect = "mouseclick";

QDBusInterface kwinEffects()
{
    return QDBusInterface(QLatin1String(kwinService), QLatin1String(effectsPath),
                          QLatin1String(effectsInterface), QDBusConnection::sessionBus());
}

}

/**
 * KWin's mouseclick effect exists for exactly this ("useful for
 * screenrecordings/presentations"), and drawing our own is not an option: a
 * click-through overlay never receives pointer events, so a Wayland client
 * cannot know where the cursor is.
 */
bool RecorderBackend::clickHighlightSupported() const
{
    auto effects = kwinEffects();
    if (!effects.isValid())
        return false;
    const QDBusReply<bool> reply = effects.call(QStringLiteral("isEffectSupported"),
                                                QLatin1String(clickEffect));
    return reply.isValid() && reply.value();
}

// The effect only exposes a stateless toggle shortcut, but it reports its state
// in the support dump, so the toggle can be driven to a known value.
bool RecorderBackend::clickEffectArmed() const
{
    auto effects = kwinEffects();
    if (!effects.isValid())
        return false;
    const QDBusReply<QString> reply = effects.call(QStringLiteral("supportInformation"),
                                                   QLatin1String(clickEffect));
    if (!reply.isValid())
        return false;
    for (const QString &line : reply.value().split(QLatin1Char('\n'))) {
        if (line.trimmed().startsWith(QLatin1String("enabled:")))
            return line.trimmed().endsWith(QLatin1String("true"));
    }
    return false;
}

void RecorderBackend::armClickEffect(bool armed)
{
    auto effects = kwinEffects();
    if (!effects.isValid())
        return;

    if (armed) {
        const QDBusReply<bool> loaded = effects.call(QStringLiteral("isEffectLoaded"),
                                                     QLatin1String(clickEffect));
        if (loaded.isValid() && !loaded.value()) {
            seedClickEffectDefaults();
            effects.call(QStringLiteral("loadEffect"), QLatin1String(clickEffect));
            m_clickEffectLoadedHere = true;
        }
    }

    if (clickEffectArmed() != armed) {
        QDBusInterface(QStringLiteral("org.kde.kglobalaccel"),
                       QStringLiteral("/component/kwin"),
                       QStringLiteral("org.kde.kglobalaccel.Component"),
                       QDBusConnection::sessionBus())
            .call(QStringLiteral("invokeShortcut"), QStringLiteral("ToggleMouseClick"));
    }

    // Leaving an effect loaded that the user never enabled themselves would show
    // up in their System Settings as ours.
    if (!armed && m_clickEffectLoadedHere) {
        effects.call(QStringLiteral("unloadEffect"), QLatin1String(clickEffect));
        m_clickEffectLoadedHere = false;
    }
}

// A 20px ring one pixel wide is what KWin ships and is invisible on a 4K screen,
// so give the effect usable defaults the first time. An existing group means the
// user has their own settings and they are left alone.
void RecorderBackend::seedClickEffectDefaults() const
{
    if (QStandardPaths::findExecutable(QStringLiteral("kwriteconfig6")).isEmpty())
        return;
    QSettings kwin(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                       + QStringLiteral("/kwinrc"),
                   QSettings::IniFormat);
    if (kwin.childGroups().contains(QStringLiteral("Effect-mouseclick")))
        return;

    const QList<QPair<QString, QString>> defaults{
        {QStringLiteral("RingSize"), QStringLiteral("60")},
        {QStringLiteral("LineWidth"), QStringLiteral("4")},
        {QStringLiteral("RingCount"), QStringLiteral("3")},
        {QStringLiteral("ShowText"), QStringLiteral("false")},
    };
    for (const auto &[key, value] : defaults) {
        QProcess::execute(QStringLiteral("kwriteconfig6"),
                          {QStringLiteral("--file"), QStringLiteral("kwinrc"),
                           QStringLiteral("--group"), QStringLiteral("Effect-mouseclick"),
                           QStringLiteral("--key"), key, value});
    }
    // reconfigureEffect only re-reads KWin's in-memory config; the values above
    // were written to the file by another process, so KWin has to reload first.
    QDBusInterface(QLatin1String(kwinService), QStringLiteral("/KWin"),
                   QLatin1String(kwinService), QDBusConnection::sessionBus())
        .call(QStringLiteral("reconfigure"));
    kwinEffects().call(QStringLiteral("reconfigureEffect"), QLatin1String(clickEffect));
}

void RecorderBackend::syncClickHighlight()
{
    const bool wanted = m_recording && m_highlightClicks;
    if (wanted == m_clickHighlightActive)
        return;
    m_clickHighlightActive = wanted;
    armClickEffect(wanted);
}

void RecorderBackend::setHighlightClicks(bool value)
{
    if (value == m_highlightClicks)
        return;
    m_highlightClicks = value;
    saveSetting(QStringLiteral("highlightClicks"), value);
    syncClickHighlight();
    emit settingsChanged();
}

void RecorderBackend::setWebcamEnabled(bool value)
{
    if (value == m_webcamEnabled)
        return;
    m_webcamEnabled = value;
    saveSetting(QStringLiteral("webcamEnabled"), value);
    emit settingsChanged();
}

void RecorderBackend::setWebcamShape(const QString &value)
{
    const QString clean = oneOf(value, {QStringLiteral("circle"), QStringLiteral("square")},
                                QStringLiteral("circle"));
    if (clean == m_webcamShape)
        return;
    m_webcamShape = clean;
    saveSetting(QStringLiteral("webcamShape"), clean);
    emit settingsChanged();
}

void RecorderBackend::setWebcamCorner(const QString &value)
{
    const QString clean = oneOf(value,
                                {QStringLiteral("topLeft"), QStringLiteral("topRight"),
                                 QStringLiteral("bottomLeft"), QStringLiteral("bottomRight")},
                                QStringLiteral("bottomRight"));
    if (clean == m_webcamCorner)
        return;
    m_webcamCorner = clean;
    saveSetting(QStringLiteral("webcamCorner"), clean);
    emit settingsChanged();
}

void RecorderBackend::setWebcamSize(const QString &value)
{
    const QString clean = oneOf(value,
                                {QStringLiteral("small"), QStringLiteral("medium"), QStringLiteral("large")},
                                QStringLiteral("medium"));
    if (clean == m_webcamSize)
        return;
    m_webcamSize = clean;
    saveSetting(QStringLiteral("webcamSize"), clean);
    emit settingsChanged();
}

void RecorderBackend::setWebcamDevice(const QString &value)
{
    if (value == m_webcamDevice)
        return;
    m_webcamDevice = value;
    saveSetting(QStringLiteral("webcamDevice"), value);
    emit settingsChanged();
}

void RecorderBackend::setWebcamMirrored(bool value)
{
    if (value == m_webcamMirrored)
        return;
    m_webcamMirrored = value;
    saveSetting(QStringLiteral("webcamMirrored"), value);
    emit settingsChanged();
}

void RecorderBackend::pushKeystrokeOptions()
{
    if (!m_recording)
        return;
    QJsonObject response;
    const QJsonObject options{
        {QStringLiteral("keystrokes"), m_showKeystrokes},
        {QStringLiteral("keystroke_hold"), m_keystrokeHoldSeconds},
    };
    if (request({
            {QStringLiteral("action"), QStringLiteral("keystrokes")},
            {QStringLiteral("options"), options},
        }, &response, false))
        applyResponse(response);
}

void RecorderBackend::setKeystrokeHoldSeconds(double value)
{
    const double clamped = qBound(0.5, value, 15.0);
    if (qFuzzyCompare(clamped, m_keystrokeHoldSeconds))
        return;
    m_keystrokeHoldSeconds = clamped;
    saveSetting(QStringLiteral("keystrokeHoldSeconds"), clamped);
    pushKeystrokeOptions();
    emit settingsChanged();
}

QString RecorderBackend::keystrokePath() const
{
    return QFileInfo(socketPath()).dir().filePath(QStringLiteral("keys.json"));
}

void RecorderBackend::syncKeystrokePolling()
{
    const bool wanted = m_recording && m_showKeystrokes;
    if (!wanted) {
        if (m_keystrokeTimer)
            m_keystrokeTimer->stop();
        clearKeystrokes();
        return;
    }
    if (!m_keystrokeTimer) {
        m_keystrokeTimer = new QTimer(this);
        m_keystrokeTimer->setInterval(50);
        connect(m_keystrokeTimer, &QTimer::timeout, this, &RecorderBackend::pollKeystrokes);
    }
    if (!m_keystrokeTimer->isActive())
        m_keystrokeTimer->start();
}

void RecorderBackend::clearKeystrokes()
{
    m_keystrokeRaw.clear();
    m_keystrokeCutoffId = 0;
    const bool hadContent = !m_keystrokeTokens.isEmpty() || m_keystrokesVisible;
    m_keystrokeTokens.clear();
    m_keystrokesVisible = false;
    if (hadContent)
        emit keystrokesChanged();
}

void RecorderBackend::pollKeystrokes()
{
    QFile file(keystrokePath());
    QByteArray raw;
    if (file.open(QIODevice::ReadOnly))
        raw = file.readAll();

    bool changed = false;
    if (raw != m_keystrokeRaw) {
        m_keystrokeRaw = raw;
        const QJsonObject snapshot = QJsonDocument::fromJson(raw).object();
        QVariantList tokens;
        for (const QJsonValue &entry : snapshot.value(QStringLiteral("tokens")).toArray()) {
            const QJsonObject token = entry.toObject();
            const qint64 id = token.value(QStringLiteral("id")).toInteger();
            if (id <= m_keystrokeCutoffId)
                continue;
            tokens.append(QVariantMap{
                {QStringLiteral("tokenId"), id},
                {QStringLiteral("text"), token.value(QStringLiteral("text")).toString()},
                {QStringLiteral("count"), token.value(QStringLiteral("count")).toInt()},
            });
        }
        const double hold = snapshot.value(QStringLiteral("hold_seconds")).toDouble();
        if (hold > 0)
            m_keystrokeHoldMs = int(hold * 1000);
        const QDateTime stamp = QDateTime::fromString(
            snapshot.value(QStringLiteral("updated_at")).toString(), Qt::ISODateWithMs);
        if (stamp.isValid())
            m_keystrokeUpdatedMs = stamp.toMSecsSinceEpoch();
        const QString error = snapshot.value(QStringLiteral("error")).toString();
        if (error != m_keystrokeError) {
            m_keystrokeError = error;
            changed = true;
        }
        if (tokens != m_keystrokeTokens) {
            m_keystrokeTokens = tokens;
            changed = true;
        }
    }

    const bool faded = QDateTime::currentMSecsSinceEpoch() - m_keystrokeUpdatedMs > m_keystrokeHoldMs;
    const bool visible = !m_keystrokeTokens.isEmpty() && !faded;
    if (visible != m_keystrokesVisible) {
        m_keystrokesVisible = visible;
        changed = true;
    }
    // Once the row has faded, anything still in the snapshot belongs to the old
    // row; drop it so the next key starts a fresh row at the left edge.
    if (faded && !m_keystrokeTokens.isEmpty()) {
        for (const QVariant &token : std::as_const(m_keystrokeTokens))
            m_keystrokeCutoffId = qMax(m_keystrokeCutoffId, token.toMap().value(QStringLiteral("tokenId")).toLongLong());
        m_keystrokeTokens.clear();
        changed = true;
    }
    if (changed)
        emit keystrokesChanged();
}

void RecorderBackend::setStartDelaySeconds(int value)
{
    const int clamped = qBound(0, value, 30);
    if (clamped == m_startDelaySeconds)
        return;
    m_startDelaySeconds = clamped;
    saveSetting(QStringLiteral("startDelaySeconds"), clamped);
    emit settingsChanged();
}

void RecorderBackend::startRecording()
{
    if (m_choosingSource) {
        abandonCaptureSelection();
        return;
    }
    if (m_countdownRemaining > 0) {
        cancelCountdown();
        return;
    }
    if (m_processingTrim) {
        setError(QStringLiteral("Wait for post-processing to finish before starting another recording."));
        return;
    }
    if (m_captureSource == QStringLiteral("region") && m_captureRegion.isEmpty()) {
        setError(QStringLiteral("Drag a region to capture before recording."));
        return;
    }
    if (!m_recording && m_captureSource == QStringLiteral("portal") && !m_selectionReady) {
        if (prepareCaptureSelection())
            return;
    }
    beginCountdown();
}

void RecorderBackend::beginCountdown()
{
    if (m_startDelaySeconds <= 0 || m_recording) {
        beginRecording();
        return;
    }

    if (!m_countdownTimer) {
        m_countdownTimer = new QTimer(this);
        m_countdownTimer->setInterval(1000);
        connect(m_countdownTimer, &QTimer::timeout, this, [this] {
            --m_countdownRemaining;
            emit countdownChanged();
            if (m_countdownRemaining > 0) {
                playCountdownTick(m_countdownRemaining == 1);
                return;
            }
            m_countdownTimer->stop();
            beginRecording();
        });
    }
    m_countdownRemaining = m_startDelaySeconds;
    emit countdownChanged();
    playCountdownTick(m_countdownRemaining == 1);
    m_countdownTimer->start();
}

bool RecorderBackend::prepareCaptureSelection()
{
    QJsonObject response;
    if (!request({{QStringLiteral("action"), QStringLiteral("prepare-selection")}}, &response, true, 4000)) {
        m_startAfterSelection = false;
        return false;
    }
    m_startAfterSelection = true;
    applyResponse(response);
    if (!m_choosingSource) {
        m_startAfterSelection = false;
        return false;
    }
    setPollInterval(200);
    return true;
}

void RecorderBackend::abandonCaptureSelection()
{
    m_startAfterSelection = false;
    QJsonObject response;
    if (request({{QStringLiteral("action"), QStringLiteral("cancel-selection")}}, &response, true, 4000))
        applyResponse(response);
}

void RecorderBackend::setPollInterval(int milliseconds)
{
    if (m_pollTimer && m_pollTimer->interval() != milliseconds)
        m_pollTimer->setInterval(milliseconds);
}

void RecorderBackend::cancelCountdown()
{
    if (m_countdownTimer)
        m_countdownTimer->stop();
    if (m_countdownRemaining == 0)
        return;
    m_countdownRemaining = 0;
    emit countdownChanged();
}

void RecorderBackend::beginRecording()
{
    QStringList audio;
    if (m_desktopAudioEnabled)
        audio << m_outputDevice;
    if (m_microphoneEnabled)
        audio << m_inputDevice;

    QString codec = QStringLiteral("h264");
    QString quality = QStringLiteral("very_high");
    int fps = 60;
    if (m_qualityPreset == QStringLiteral("crisp")) {
        codec = QStringLiteral("hevc");
        quality = QStringLiteral("ultra");
    } else if (m_qualityPreset == QStringLiteral("compact")) {
        codec = QStringLiteral("hevc");
        quality = QStringLiteral("high");
        fps = 30;
    }

    QJsonObject options{
        {QStringLiteral("capture"), m_captureSource},
        {QStringLiteral("fps"), fps},
        {QStringLiteral("audio"), audio.join(QLatin1Char('|'))},
        {QStringLiteral("codec"), codec},
        {QStringLiteral("quality"), quality},
        {QStringLiteral("output_directory"), m_outputDirectory},
        {QStringLiteral("cursor"), m_captureCursor},
        {QStringLiteral("keystrokes"), m_showKeystrokes},
        {QStringLiteral("keystroke_hold"), m_keystrokeHoldSeconds},
    };
    if (m_captureSource == QStringLiteral("region"))
        options.insert(QStringLiteral("region"), m_captureRegion);
    if (m_captureSource == QStringLiteral("portal"))
        options.insert(QStringLiteral("restore_portal_session"), m_selectionReady);
    QJsonObject response;
    m_activeCodec = codec;
    if (request({
            {QStringLiteral("action"), QStringLiteral("start")},
            {QStringLiteral("options"), options},
        }, &response, true)) {
        applyResponse(response);
    }
}

void RecorderBackend::stopRecording()
{
    if (m_countdownRemaining > 0) {
        cancelCountdown();
        return;
    }
    QJsonObject response;
    if (request({{QStringLiteral("action"), QStringLiteral("stop")}}, &response, true, 13000))
        applyResponse(response);
}

void RecorderBackend::discardRecording()
{
    if (m_countdownRemaining > 0) {
        cancelCountdown();
        return;
    }
    QJsonObject response;
    if (!request({{QStringLiteral("action"), QStringLiteral("discard")}}, &response, true, 13000))
        return;
    const bool wasRecording = m_recording;
    applyResponse(response);
    if (wasRecording && !m_recording) {
        playDiscardCue();
        m_lastNotificationPath.clear();
        if (m_tray)
            m_tray->showMessage(QStringLiteral("Recording discarded"),
                                QStringLiteral("Nothing was saved."),
                                QSystemTrayIcon::Information, 4000);
    }
}

void RecorderBackend::togglePause()
{
    QJsonObject response;
    if (request({{QStringLiteral("action"), QStringLiteral("toggle-pause")}}, &response, true))
        applyResponse(response);
}

void RecorderBackend::refreshState()
{
    QJsonObject response;
    if (request({{QStringLiteral("action"), QStringLiteral("status")}}, &response, false))
        applyResponse(response);
}

void RecorderBackend::refreshDevices()
{
    m_monitors = discover(QStringLiteral("--list-monitors"), false);
    m_monitors.prepend(QVariantMap{
        {"value", "screen"},
        {"name", "Primary display"},
        {"detail", "Automatic"},
    });
    m_outputDevices = discover(QStringLiteral("--list-audio-devices"), false);
    m_inputDevices = discover(QStringLiteral("--list-audio-devices"), true);

    if (m_outputDevices.isEmpty())
        m_outputDevices.append(QVariantMap{{"value", "default_output"}, {"name", "Default output"}});
    if (m_inputDevices.isEmpty())
        m_inputDevices.append(QVariantMap{{"value", "default_input"}, {"name", "Default input"}});

    if (m_outputDevice.isEmpty())
        m_outputDevice = firstValue(m_outputDevices, QStringLiteral("default_output"));
    if (m_inputDevice.isEmpty())
        m_inputDevice = firstValue(m_inputDevices, QStringLiteral("default_input"));
    emit devicesChanged();
}

void RecorderBackend::startService()
{
    setError(QStringLiteral("Starting the recorder service…"));
    QProcess::startDetached(QStringLiteral("systemctl"),
                            {QStringLiteral("--user"), QStringLiteral("start"),
                             QStringLiteral("remcorder.service")});
    QTimer::singleShot(900, this, [this] {
        QJsonObject response;
        if (request({{QStringLiteral("action"), QStringLiteral("status")}}, &response, false)) {
            applyResponse(response);
            setError({});
        } else {
            setError(QStringLiteral("The recorder service is unavailable. Install it with “make install”, then try again."));
        }
    });
}

void RecorderBackend::openOutputDirectory()
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(m_outputDirectory));
}

void RecorderBackend::chooseOutputDirectory()
{
    const QString directory = QFileDialog::getExistingDirectory(
        nullptr, QStringLiteral("Choose where recordings are saved"), m_outputDirectory);
    if (!directory.isEmpty())
        setOutputDirectory(directory);
}

void RecorderBackend::openLastRecording()
{
    if (!m_lastOutputFile.isEmpty())
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_lastOutputFile));
}

QString RecorderBackend::chooseVideoToTrim()
{
    return QFileDialog::getOpenFileName(
        nullptr,
        QStringLiteral("Choose a recording to trim"),
        m_outputDirectory,
        QStringLiteral("Video files (*.mp4 *.mkv *.webm *.mov);;All files (*)"));
}

void RecorderBackend::exportTrim(const QString &source,
                                 double startSeconds,
                                 double endSeconds,
                                 bool motionBlur,
                                 const QString &motionBlurStrength)
{
    if (m_recording || m_processingTrim) {
        setError(QStringLiteral("Wait for the current recording or post-processing task to finish."));
        return;
    }
    if (!QFileInfo::exists(source)) {
        setError(QStringLiteral("The selected recording is no longer available."));
        return;
    }
    if (startSeconds < 0.0 || endSeconds - startSeconds < 0.25) {
        setError(QStringLiteral("Choose at least a quarter-second range to export."));
        return;
    }

    const QString ffmpeg = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    if (ffmpeg.isEmpty()) {
        setError(QStringLiteral("FFmpeg is unavailable, so the trim could not start."));
        return;
    }

    m_trimOutputFile = trimOutputPath(source, motionBlur);
    const QFileInfo outputInfo(m_trimOutputFile);
    m_trimTemporaryFile = outputInfo.dir().filePath(
        QStringLiteral(".%1.partial.mp4").arg(outputInfo.completeBaseName()));
    QFile::remove(m_trimTemporaryFile);

    QString encoder;
    const QStringList encoderOptions = videoEncoderOptions(&encoder);
    const double selectedDuration = endSeconds - startSeconds;
    QStringList arguments{
        QStringLiteral("-hide_banner"),
        QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-nostdin"),
        QStringLiteral("-y"),
        QStringLiteral("-ss"), QString::number(startSeconds, 'f', 3),
        QStringLiteral("-i"), source,
        QStringLiteral("-t"), QString::number(selectedDuration, 'f', 3),
    };
    if (motionBlur)
        arguments.append({QStringLiteral("-vf"), motionBlurFilter(motionBlurStrength)});
    arguments.append({
        QStringLiteral("-map"), QStringLiteral("0:v:0"),
        QStringLiteral("-map"), QStringLiteral("0:a?"),
        QStringLiteral("-c:v"), encoder,
    });
    arguments.append(encoderOptions);
    arguments.append({
        QStringLiteral("-c:a"), QStringLiteral("aac"),
        QStringLiteral("-b:a"), QStringLiteral("192k"),
        QStringLiteral("-movflags"), QStringLiteral("+faststart"),
        QStringLiteral("-progress"), QStringLiteral("pipe:1"),
        QStringLiteral("-nostats"),
        m_trimTemporaryFile,
    });

    m_trimDurationMilliseconds = qMax<qint64>(
        250, static_cast<qint64>(selectedDuration * 1000.0));
    m_trimProgress = 0;
    m_trimProgressBuffer.clear();
    m_processingTrim = true;
    m_trimProcess = new QProcess(this);
    m_trimProcess->setProcessChannelMode(QProcess::SeparateChannels);
    connect(m_trimProcess, &QProcess::readyReadStandardOutput,
            this, &RecorderBackend::updateTrimProgress);
    connect(m_trimProcess, &QProcess::finished,
            this, &RecorderBackend::finishTrim);
    m_trimProcess->start(ffmpeg, arguments);
    if (!m_trimProcess->waitForStarted(1500)) {
        setError(QStringLiteral("Trim export could not start. The source recording is unchanged."));
        m_trimProcess->deleteLater();
        m_trimProcess = nullptr;
        m_processingTrim = false;
    }
    emit trimStateChanged();
    updateTray();
}

void RecorderBackend::openLastTrimmedRecording()
{
    if (!m_lastTrimmedOutputFile.isEmpty())
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_lastTrimmedOutputFile));
}

void RecorderBackend::copyLastOutputPath()
{
    if (m_lastOutputFile.isEmpty())
        return;
    QGuiApplication::clipboard()->setText(m_lastOutputFile);
}

void RecorderBackend::openRecentRecording(const QString &path)
{
    if (!path.isEmpty() && QFileInfo::exists(path))
        QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void RecorderBackend::revealRecording(const QString &path)
{
    if (path.isEmpty())
        return;
    const QFileInfo info(path);
    if (info.exists()) {
        QDBusInterface fileManager(QStringLiteral("org.freedesktop.FileManager1"),
                                   QStringLiteral("/org/freedesktop/FileManager1"),
                                   QStringLiteral("org.freedesktop.FileManager1"),
                                   QDBusConnection::sessionBus());
        if (fileManager.isValid()) {
            const QDBusReply<void> reply = fileManager.call(
                QStringLiteral("ShowItems"),
                QStringList{QUrl::fromLocalFile(info.absoluteFilePath()).toString()},
                QString());
            if (reply.isValid())
                return;
        }
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(info.absolutePath()));
}

void RecorderBackend::revealLastRecording()
{
    revealRecording(m_lastOutputFile);
}

QString RecorderBackend::renameLastRecording(const QString &name)
{
    if (m_lastOutputFile.isEmpty())
        return QStringLiteral("There is no recording to rename.");
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty())
        return QStringLiteral("Give the recording a name.");
    if (trimmed.contains(QLatin1Char('/')))
        return QStringLiteral("Use a plain file name without slashes.");
    const QString previous = m_lastOutputFile;
    QJsonObject response;
    if (!request({{QStringLiteral("action"), QStringLiteral("rename")},
                  {QStringLiteral("path"), trimmed}},
                 &response, true))
        return m_errorMessage.isEmpty() ? QStringLiteral("The recording could not be renamed.") : m_errorMessage;
    applyResponse(response);
    if (m_lastOutputFile == previous)
        return {};
    if (m_lastNotificationPath == previous)
        m_lastNotificationPath = m_lastOutputFile;
    const int recentIndex = m_recentRecordings.indexOf(QVariant(previous));
    if (recentIndex >= 0) {
        m_recentRecordings[recentIndex] = m_lastOutputFile;
        saveSetting(QStringLiteral("recentRecordings"), m_recentRecordings);
        emit recentRecordingsChanged();
        updateRecentMenu();
    }
    return {};
}

QVariantMap RecorderBackend::recordingInfo(const QString &path) const
{
    const QFileInfo info(path);
    return QVariantMap{
        {QStringLiteral("exists"), info.exists()},
        {QStringLiteral("fileName"), info.fileName()},
        {QStringLiteral("baseName"), info.completeBaseName()},
        {QStringLiteral("suffix"), info.suffix()},
        {QStringLiteral("directory"), info.absolutePath()},
        {QStringLiteral("sizeBytes"), info.exists() ? info.size() : 0},
        {QStringLiteral("sizeLabel"), info.exists() ? formatBytes(info.size()) : QString()},
        {QStringLiteral("modifiedMs"), info.exists() ? info.lastModified().toMSecsSinceEpoch() : 0},
    };
}

QString RecorderBackend::formatBytes(qint64 bytes) const
{
    constexpr double kib = 1024.0;
    if (bytes < kib)
        return QStringLiteral("%1 B").arg(bytes);
    if (bytes < kib * kib)
        return QStringLiteral("%1 KB").arg(bytes / kib, 0, 'f', 0);
    if (bytes < kib * kib * kib)
        return QStringLiteral("%1 MB").arg(bytes / (kib * kib), 0, 'f', 1);
    return QStringLiteral("%1 GB").arg(bytes / (kib * kib * kib), 0, 'f', 2);
}

QString RecorderBackend::formatDuration(qint64 seconds) const
{
    seconds = qMax<qint64>(0, seconds);
    const qint64 hours = seconds / 3600;
    const qint64 minutes = (seconds % 3600) / 60;
    const qint64 remaining = seconds % 60;
    if (hours > 0)
        return QStringLiteral("%1:%2:%3").arg(hours, 2, 10, QLatin1Char('0'))
            .arg(minutes, 2, 10, QLatin1Char('0')).arg(remaining, 2, 10, QLatin1Char('0'));
    return QStringLiteral("%1:%2").arg(minutes, 2, 10, QLatin1Char('0'))
        .arg(remaining, 2, 10, QLatin1Char('0'));
}

bool RecorderBackend::request(const QJsonObject &payload,
                              QJsonObject *response,
                              bool showTransportError,
                              int timeoutMilliseconds)
{
    if (m_requestInFlight)
        return false;
    m_requestInFlight = true;
    const auto release = qScopeGuard([this] { m_requestInFlight = false; });

    QLocalSocket socket;
    socket.connectToServer(socketPath(), QIODevice::ReadWrite);
    if (!socket.waitForConnected(250)) {
        setServiceAvailable(false);
        if (showTransportError)
            setError(QStringLiteral("The recorder service is not running."));
        return false;
    }

    QByteArray message = QJsonDocument(payload).toJson(QJsonDocument::Compact);
    message.append('\n');
    socket.write(message);
    if (!socket.waitForBytesWritten(250)) {
        if (showTransportError)
            setError(QStringLiteral("Could not send the command to the recorder."));
        return false;
    }

    QElapsedTimer budget;
    budget.start();
    QByteArray data;
    while (!data.contains('\n')) {
        const int remaining = timeoutMilliseconds - static_cast<int>(budget.elapsed());
        if (remaining <= 0)
            break;
        if (!socket.waitForReadyRead(qMin(remaining, 200))) {
            if (socket.state() != QLocalSocket::ConnectedState)
                break;
            continue;
        }
        data += socket.readAll();
    }
    const QJsonDocument document = QJsonDocument::fromJson(data);
    if (!document.isObject()) {
        if (showTransportError)
            setError(QStringLiteral("The recorder returned an unreadable response."));
        return false;
    }

    *response = document.object();
    setServiceAvailable(true);
    const bool ok = response->value(QStringLiteral("ok")).toBool();
    if (!ok) {
        setError(response->value(QStringLiteral("error")).toString(QStringLiteral("Recording command failed.")));
        applyResponse(*response);
        return false;
    }
    setError({});
    return true;
}

void RecorderBackend::applyResponse(const QJsonObject &response)
{
    const QJsonObject state = response.value(QStringLiteral("state")).toObject();
    const bool wasRecording = m_recording;
    const QString previousLast = m_lastOutputFile;

    const bool wasChoosingSource = m_choosingSource;
    const bool wasCapturing = m_recording && !m_awaitingFirstFrame;

    m_recording = state.value(QStringLiteral("recording")).toBool();
    m_paused = state.value(QStringLiteral("paused")).toBool();
    m_durationSeconds = state.value(QStringLiteral("duration_seconds")).toInteger();
    m_outputFile = state.value(QStringLiteral("output_file")).toString();
    m_lastOutputFile = state.value(QStringLiteral("last_output_file")).toString();
    m_awaitingFirstFrame = state.value(QStringLiteral("awaiting_first_frame")).toBool();
    m_choosingSource = state.value(QStringLiteral("selecting")).toBool();
    m_selectionReady = state.value(QStringLiteral("selection_ready")).toBool();

    const QString stateError = state.value(QStringLiteral("last_error")).toString();
    if (!stateError.isEmpty())
        setError(stateError);

    emit stateChanged();
    updateTray();
    syncKeystrokePolling();
    syncClickHighlight();

    if (wasChoosingSource && !m_choosingSource) {
        setPollInterval(1000);
        const bool wanted = m_startAfterSelection;
        m_startAfterSelection = false;
        // applyResponse runs inside a daemon request; queue so the next one is not refused.
        if (wanted && m_selectionReady)
            QTimer::singleShot(0, this, &RecorderBackend::beginCountdown);
    }

    if (m_recording && m_awaitingFirstFrame)
        setPollInterval(200);
    else if (!m_choosingSource)
        setPollInterval(1000);

    if (!wasCapturing && m_recording && !m_awaitingFirstFrame) {
        setMicPlaybackEnabled(false);
        playStartCue();
    }

    const bool justFinished = wasRecording && !m_recording
        && !m_lastOutputFile.isEmpty() && m_lastOutputFile != previousLast;
    if (justFinished) {
        playStopCue();
        notifyTray(QStringLiteral("Recording saved"), m_lastOutputFile);
        rememberRecentRecording(m_lastOutputFile);
        emit recordingSaved(m_lastOutputFile);
    }
}

void RecorderBackend::setError(const QString &message)
{
    if (message == m_errorMessage)
        return;
    m_errorMessage = message;
    emit errorChanged();
}

void RecorderBackend::setServiceAvailable(bool available)
{
    if (available == m_serviceAvailable)
        return;
    m_serviceAvailable = available;
    emit serviceAvailableChanged();
    updateTray();
}

void RecorderBackend::loadSettings()
{
    QSettings settings(organization, application);
    m_captureSource = settings.value(QStringLiteral("captureSource"), QStringLiteral("screen")).toString();
    m_captureRegion = settings.value(QStringLiteral("captureRegion")).toString();
    m_desktopAudioEnabled = settings.value(QStringLiteral("desktopAudioEnabled"), true).toBool();
    m_microphoneEnabled = settings.value(QStringLiteral("microphoneEnabled"), false).toBool();
    m_outputDevice = settings.value(QStringLiteral("outputDevice"), QStringLiteral("default_output")).toString();
    m_inputDevice = settings.value(QStringLiteral("inputDevice"), QStringLiteral("default_input")).toString();
    m_qualityPreset = settings.value(QStringLiteral("qualityPreset"), QStringLiteral("balanced")).toString();
    m_captureCursor = settings.value(QStringLiteral("captureCursor"), true).toBool();
    m_lastTrimmedOutputFile = settings.value(
        QStringLiteral("lastTrimmedOutputFile")).toString();
    if (!QFileInfo::exists(m_lastTrimmedOutputFile))
        m_lastTrimmedOutputFile.clear();
    m_soundCuesEnabled = settings.value(QStringLiteral("soundCuesEnabled"), true).toBool();
    m_showKeystrokes = settings.value(QStringLiteral("showKeystrokes"), false).toBool();
    m_keystrokeHoldSeconds = qBound(
        0.5, settings.value(QStringLiteral("keystrokeHoldSeconds"), 2.5).toDouble(), 15.0);
    m_keystrokePlacement = settings.value(
        QStringLiteral("keystrokePlacement"), QStringLiteral("pill")).toString();
    m_highlightClicks = settings.value(QStringLiteral("highlightClicks"), false).toBool();
    m_webcamEnabled = settings.value(QStringLiteral("webcamEnabled"), false).toBool();
    m_webcamShape = oneOf(settings.value(QStringLiteral("webcamShape")).toString(),
                          {QStringLiteral("circle"), QStringLiteral("square")},
                          QStringLiteral("circle"));
    m_webcamCorner = oneOf(settings.value(QStringLiteral("webcamCorner")).toString(),
                           {QStringLiteral("topLeft"), QStringLiteral("topRight"),
                            QStringLiteral("bottomLeft"), QStringLiteral("bottomRight")},
                           QStringLiteral("bottomRight"));
    m_webcamSize = oneOf(settings.value(QStringLiteral("webcamSize")).toString(),
                         {QStringLiteral("small"), QStringLiteral("medium"), QStringLiteral("large")},
                         QStringLiteral("medium"));
    m_webcamDevice = settings.value(QStringLiteral("webcamDevice")).toString();
    m_webcamMirrored = settings.value(QStringLiteral("webcamMirrored"), true).toBool();
    m_startDelaySeconds = qBound(
        0, settings.value(QStringLiteral("startDelaySeconds"), 0).toInt(), 30);
    m_recentRecordings.clear();
    for (const QVariant &entry : settings.value(QStringLiteral("recentRecordings")).toList()) {
        if (QFileInfo::exists(entry.toString()))
            m_recentRecordings.append(entry);
    }

    const QString movies = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    m_outputDirectory = settings.value(
        QStringLiteral("outputDirectory"),
        QDir(movies.isEmpty() ? QDir::homePath() : movies).filePath(QStringLiteral("Recordings"))
    ).toString();
}

void RecorderBackend::saveSetting(const QString &key, const QVariant &value)
{
    QSettings settings(organization, application);
    settings.setValue(key, value);
}

void RecorderBackend::setupTray()
{
    if (!trayAvailable())
        return;

    m_tray = new QSystemTrayIcon(branding::trayIcon(), this);
    m_trayMenu = new QMenu;
    m_showAction = m_trayMenu->addAction(QStringLiteral("Open Remcorder"));
    m_trayMenu->addSeparator();
    m_recordAction = m_trayMenu->addAction(QStringLiteral("Start recording"));
    m_pauseAction = m_trayMenu->addAction(QStringLiteral("Pause"));
    m_stopAction = m_trayMenu->addAction(QStringLiteral("Stop and save"));
    m_discardAction = m_trayMenu->addAction(QStringLiteral("Stop without saving"));
    m_keystrokesAction = m_trayMenu->addAction(QStringLiteral("Show keystrokes"));
    m_keystrokesAction->setCheckable(true);
    m_keystrokesAction->setChecked(m_showKeystrokes);
    m_trayMenu->addSeparator();
    m_openAction = m_trayMenu->addAction(QStringLiteral("Open recordings folder"));
    m_revealAction = m_trayMenu->addAction(QStringLiteral("Show last recording in folder"));
    m_openTrimAction = m_trayMenu->addAction(QStringLiteral("Open last trimmed copy"));
    m_copyPathAction = m_trayMenu->addAction(QStringLiteral("Copy last recording path"));
    m_recentMenu = m_trayMenu->addMenu(QStringLiteral("Recent recordings"));
    m_quitAction = m_trayMenu->addAction(QStringLiteral("Quit"));

    connect(m_showAction, &QAction::triggered, this, &RecorderBackend::requestShow);
    connect(m_recordAction, &QAction::triggered, this, [this] {
        if (m_recording)
            emit requestShow();
        else
            startRecording();
    });
    connect(m_pauseAction, &QAction::triggered, this, &RecorderBackend::togglePause);
    connect(m_stopAction, &QAction::triggered, this, &RecorderBackend::stopRecording);
    connect(m_discardAction, &QAction::triggered, this, &RecorderBackend::discardRecording);
    connect(m_keystrokesAction, &QAction::toggled, this, &RecorderBackend::setShowKeystrokes);
    connect(m_openAction, &QAction::triggered, this, &RecorderBackend::openOutputDirectory);
    connect(m_revealAction, &QAction::triggered, this, &RecorderBackend::revealLastRecording);
    connect(m_openTrimAction, &QAction::triggered,
            this, &RecorderBackend::openLastTrimmedRecording);
    connect(m_copyPathAction, &QAction::triggered, this, &RecorderBackend::copyLastOutputPath);
    connect(m_quitAction, &QAction::triggered, qApp, &QCoreApplication::quit);
    connect(m_tray, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick)
            emit requestShow();
    });
    connect(m_tray, &QSystemTrayIcon::messageClicked, this, [this] {
        if (!m_lastNotificationPath.isEmpty())
            QDesktopServices::openUrl(QUrl::fromLocalFile(m_lastNotificationPath));
    });

    m_tray->setContextMenu(m_trayMenu);
    m_tray->setToolTip(QStringLiteral("Remcorder"));
    m_tray->show();
    updateRecentMenu();
    updateTray();
}

void RecorderBackend::updateTray()
{
    if (!m_tray)
        return;
    m_recordAction->setEnabled(m_serviceAvailable && !m_recording && !m_processingTrim);
    m_recordAction->setText(m_countdownRemaining > 0
                                ? QStringLiteral("Cancel countdown")
                                : m_choosingSource
                                ? QStringLiteral("Cancel selection")
                                : QStringLiteral("Start recording"));
    m_pauseAction->setEnabled(m_serviceAvailable && m_recording);
    m_pauseAction->setText(m_paused ? QStringLiteral("Resume") : QStringLiteral("Pause"));
    m_stopAction->setEnabled(m_serviceAvailable && m_recording);
    m_discardAction->setEnabled(m_serviceAvailable && m_recording);
    if (m_keystrokesAction->isChecked() != m_showKeystrokes)
        m_keystrokesAction->setChecked(m_showKeystrokes);
    m_openTrimAction->setEnabled(!m_lastTrimmedOutputFile.isEmpty() && !m_processingTrim);
    m_copyPathAction->setEnabled(!m_lastOutputFile.isEmpty());
    m_revealAction->setEnabled(!m_lastOutputFile.isEmpty());
    m_quitAction->setEnabled(!m_processingTrim);
    if (m_processingTrim) {
        m_tray->setToolTip(QStringLiteral("Exporting trim · %1%").arg(m_trimProgress));
    } else if (m_countdownRemaining > 0) {
        m_tray->setToolTip(QStringLiteral("Remcorder · Starting in %1s").arg(m_countdownRemaining));
    } else if (m_choosingSource) {
        m_tray->setToolTip(QStringLiteral("Remcorder · Choose what to record"));
    } else if (m_recording && m_awaitingFirstFrame) {
        m_tray->setToolTip(QStringLiteral("Remcorder · Waiting for the first frame"));
    } else if (m_recording) {
        m_tray->setToolTip(QStringLiteral("%1 · %2")
                               .arg(m_paused ? QStringLiteral("Paused") : QStringLiteral("Recording"),
                                    formatDuration(m_durationSeconds)));
    } else {
        m_tray->setToolTip(QStringLiteral("Remcorder · Ready"));
    }
}

void RecorderBackend::updateRecentMenu()
{
    if (!m_recentMenu)
        return;
    m_recentMenu->clear();
    if (m_recentRecordings.isEmpty()) {
        QAction *empty = m_recentMenu->addAction(QStringLiteral("No recordings yet"));
        empty->setEnabled(false);
        return;
    }
    for (const QVariant &entry : m_recentRecordings) {
        const QString path = entry.toString();
        QAction *action = m_recentMenu->addAction(QFileInfo(path).fileName());
        connect(action, &QAction::triggered, this, [this, path] { openRecentRecording(path); });
    }
}

void RecorderBackend::notifyTray(const QString &title, const QString &path)
{
    m_lastNotificationPath = path;
    if (m_tray)
        m_tray->showMessage(title, QFileInfo(path).fileName(), QSystemTrayIcon::Information, 5000);
}

void RecorderBackend::rememberRecentRecording(const QString &path)
{
    m_recentRecordings.removeAll(QVariant(path));
    m_recentRecordings.prepend(path);
    while (m_recentRecordings.size() > 5)
        m_recentRecordings.removeLast();
    saveSetting(QStringLiteral("recentRecordings"), m_recentRecordings);
    emit recentRecordingsChanged();
    updateRecentMenu();
}

void RecorderBackend::playCue(const QList<QPair<double, int>> &tones)
{
    if (!m_soundCuesEnabled || tones.isEmpty())
        return;

    const QAudioDevice device = QMediaDevices::defaultAudioOutput();
    if (device.isNull())
        return;

    QAudioFormat format;
    format.setSampleRate(44100);
    format.setChannelCount(1);
    format.setSampleFormat(QAudioFormat::Int16);
    if (!device.isFormatSupported(format))
        format = device.preferredFormat();
    if (format.sampleFormat() != QAudioFormat::Int16
        && format.sampleFormat() != QAudioFormat::Float) {
        QApplication::beep();
        return;
    }

    const QByteArray samples = renderTones(format, tones);
    if (samples.isEmpty())
        return;

    releaseCueSink();

    auto *buffer = new QBuffer(this);
    buffer->setData(samples);
    buffer->open(QIODevice::ReadOnly);
    m_cueBuffer = buffer;

    m_cueSink = new QAudioSink(device, format, this);
    connect(m_cueSink, &QAudioSink::stateChanged, this, [this](QAudio::State state) {
        if (state == QAudio::IdleState)
            releaseCueSink();
    });
    m_cueSink->start(m_cueBuffer);
}

void RecorderBackend::releaseCueSink()
{
    if (m_cueSink) {
        m_cueSink->stop();
        m_cueSink->deleteLater();
        m_cueSink = nullptr;
    }
    if (m_cueBuffer) {
        m_cueBuffer->close();
        m_cueBuffer->deleteLater();
        m_cueBuffer = nullptr;
    }
}

void RecorderBackend::playStartCue()
{
    playCue({{784.0, 80}, {0.0, 30}, {1174.7, 130}});
}

void RecorderBackend::playStopCue()
{
    playCue({{1174.7, 80}, {0.0, 30}, {587.3, 170}});
}

void RecorderBackend::playDiscardCue()
{
    playCue({{587.3, 70}, {0.0, 30}, {392.0, 170}});
}

void RecorderBackend::playCountdownTick(bool last)
{
    if (last)
        playCue({{1046.5, 150}});
    else
        playCue({{659.3, 70}});
}

void RecorderBackend::updateTrimProgress()
{
    if (!m_trimProcess)
        return;
    m_trimProgressBuffer += m_trimProcess->readAllStandardOutput();

    qsizetype newline = -1;
    while ((newline = m_trimProgressBuffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_trimProgressBuffer.left(newline).trimmed();
        m_trimProgressBuffer.remove(0, newline + 1);
        if (!line.startsWith("out_time_us="))
            continue;
        bool ok = false;
        const qint64 microseconds = line.mid(sizeof("out_time_us=") - 1).toLongLong(&ok);
        if (!ok)
            continue;
        const int progress = qBound(
            0, static_cast<int>(microseconds / (m_trimDurationMilliseconds * 10)), 99);
        if (progress != m_trimProgress) {
            m_trimProgress = progress;
            emit trimStateChanged();
            updateTray();
        }
    }
}

void RecorderBackend::finishTrim(int exitCode, QProcess::ExitStatus status)
{
    if (!m_trimProcess)
        return;

    const QString processError = QString::fromUtf8(m_trimProcess->readAllStandardError()).trimmed();
    const bool encoded = status == QProcess::NormalExit && exitCode == 0
        && QFileInfo(m_trimTemporaryFile).size() > 0;
    const bool saved = encoded && QFile::rename(m_trimTemporaryFile, m_trimOutputFile);

    if (saved) {
        m_lastTrimmedOutputFile = m_trimOutputFile;
        saveSetting(QStringLiteral("lastTrimmedOutputFile"), m_lastTrimmedOutputFile);
        m_trimProgress = 100;
        setError({});
        if (m_tray) {
            notifyTray(QStringLiteral("Trimmed copy ready"), m_trimOutputFile);
        }
    } else {
        QFile::remove(m_trimTemporaryFile);
        const QString detail = processError.isEmpty()
            ? QStringLiteral("The video encoder could not export the selected range.")
            : processError.section(QLatin1Char('\n'), -1);
        setError(QStringLiteral("The source is unchanged. Trim export failed: %1").arg(detail));
    }

    m_trimProcess->deleteLater();
    m_trimProcess = nullptr;
    m_processingTrim = false;
    emit trimStateChanged();
    updateTray();
}

QString RecorderBackend::trimOutputPath(const QString &source, bool motionBlur) const
{
    const QFileInfo sourceInfo(source);
    const QString stem = sourceInfo.completeBaseName()
        + (motionBlur ? QStringLiteral("-trim-blur") : QStringLiteral("-trim"));
    QString candidate = sourceInfo.dir().filePath(stem + QStringLiteral(".mp4"));
    int suffix = 2;
    while (QFileInfo::exists(candidate)) {
        candidate = sourceInfo.dir().filePath(
            QStringLiteral("%1-%2.mp4").arg(stem).arg(suffix++));
    }
    return candidate;
}

QStringList RecorderBackend::videoEncoderOptions(QString *encoder) const
{
    QProcess info;
    info.start(QStringLiteral("gpu-screen-recorder"), {QStringLiteral("--info")});
    info.waitForFinished(1500);
    const bool nvidia = QString::fromUtf8(info.readAllStandardOutput())
                            .contains(QStringLiteral("vendor|nvidia"));

    if (!nvidia) {
        *encoder = QStringLiteral("libx264");
        return {
            QStringLiteral("-preset"), QStringLiteral("fast"),
            QStringLiteral("-crf"), QStringLiteral("18"),
        };
    }

    if (m_activeCodec.startsWith(QStringLiteral("hevc")))
        *encoder = QStringLiteral("hevc_nvenc");
    else if (m_activeCodec.startsWith(QStringLiteral("av1")))
        *encoder = QStringLiteral("av1_nvenc");
    else
        *encoder = QStringLiteral("h264_nvenc");
    return {
        QStringLiteral("-preset"), QStringLiteral("p5"),
        QStringLiteral("-cq"), QStringLiteral("20"),
        QStringLiteral("-b:v"), QStringLiteral("0"),
    };
}

bool RecorderBackend::micGainSupported() const
{
    return !QStandardPaths::findExecutable(QStringLiteral("pactl")).isEmpty();
}

void RecorderBackend::setMicMonitorEnabled(bool value)
{
    if (value == m_micMonitorEnabled)
        return;
    m_micMonitorEnabled = value;
    emit micMonitorChanged();
    syncMicMonitor();
}

void RecorderBackend::setMicPlaybackEnabled(bool value)
{
    if (value == m_micPlaybackEnabled)
        return;
    m_micPlaybackEnabled = value;
    if (!value && m_micSink) {
        m_micSink->stop();
        m_micSink->deleteLater();
        m_micSink = nullptr;
        m_micSinkStream = nullptr;
    }
    emit micMonitorChanged();
    syncMicMonitor();
}

void RecorderBackend::setMicGain(qreal value)
{
    const qreal clamped = qBound(0.0, value, 1.5);
    if (qFuzzyCompare(clamped + 1.0, m_micGain + 1.0))
        return;
    m_micGain = clamped;
    emit micGainChanged();

    const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
    if (pactl.isEmpty())
        return;
    QProcess::startDetached(pactl, {
        QStringLiteral("set-source-volume"),
        pulseSourceName(),
        QStringLiteral("%1%").arg(qRound(clamped * 100.0)),
    });
}

void RecorderBackend::syncMicMonitor()
{
    const bool wanted = m_micMonitorEnabled && m_microphoneEnabled;
    if (wanted && !micMonitorActive())
        startMicMonitor();
    else if (!wanted && micMonitorActive())
        stopMicMonitor();
}

void RecorderBackend::startMicMonitor()
{
    QAudioDevice device = QMediaDevices::defaultAudioInput();
    if (m_inputDevice != QStringLiteral("default_input")) {
        const QList<QAudioDevice> inputs = QMediaDevices::audioInputs();
        for (const QAudioDevice &candidate : inputs) {
            if (QString::fromUtf8(candidate.id()) == m_inputDevice) {
                device = candidate;
                break;
            }
        }
    }
    if (device.isNull())
        return;

    QAudioFormat format;
    format.setSampleRate(48000);
    format.setChannelCount(1);
    format.setSampleFormat(QAudioFormat::Int16);
    if (!device.isFormatSupported(format))
        format = device.preferredFormat();

    m_micFormat = format;
    m_micDeviceName = device.description();
    m_micSource = new QAudioSource(device, format, this);
    m_micSource->setBufferSize(format.bytesForDuration(40000));
    m_micStream = m_micSource->start();
    if (!m_micStream) {
        m_micSource->deleteLater();
        m_micSource = nullptr;
        setError(QStringLiteral("The microphone could not be opened for monitoring."));
        return;
    }
    connect(m_micStream, &QIODevice::readyRead, this, &RecorderBackend::readMicSamples);

    if (!m_micDecayTimer) {
        m_micDecayTimer = new QTimer(this);
        m_micDecayTimer->setInterval(60);
        connect(m_micDecayTimer, &QTimer::timeout, this, &RecorderBackend::decayMicLevel);
    }
    m_micPeakAge.start();
    m_micDecayTimer->start();
    loadMicGain();
    emit micMonitorChanged();
}

void RecorderBackend::stopMicMonitor()
{
    if (m_micDecayTimer)
        m_micDecayTimer->stop();
    if (m_micStream)
        disconnect(m_micStream, nullptr, this, nullptr);
    m_micStream = nullptr;
    if (m_micSource) {
        m_micSource->stop();
        m_micSource->deleteLater();
        m_micSource = nullptr;
    }
    if (m_micSink) {
        m_micSink->stop();
        m_micSink->deleteLater();
        m_micSink = nullptr;
        m_micSinkStream = nullptr;
    }
    m_micLevel = 0;
    m_micPeak = 0;
    emit micLevelChanged();
    emit micMonitorChanged();
}

void RecorderBackend::readMicSamples()
{
    if (!m_micStream)
        return;
    const QByteArray chunk = m_micStream->readAll();
    if (chunk.isEmpty())
        return;

    if (m_micPlaybackEnabled && !m_micSink) {
        m_micSink = new QAudioSink(QMediaDevices::defaultAudioOutput(), m_micFormat, this);
        m_micSinkStream = m_micSink->start();
    }
    if (m_micPlaybackEnabled && m_micSinkStream)
        m_micSinkStream->write(chunk);

    const int bytesPerSample = m_micFormat.bytesPerSample();
    const int channels = m_micFormat.channelCount();
    const int frameSize = bytesPerSample * channels;
    if (frameSize <= 0)
        return;
    const qsizetype frames = chunk.size() / frameSize;
    if (frames <= 0)
        return;

    double energy = 0;
    const char *cursor = chunk.constData();
    for (qsizetype frame = 0; frame < frames; ++frame) {
        float loudest = 0;
        for (int channel = 0; channel < channels; ++channel) {
            const float sample = m_micFormat.normalizedSampleValue(
                cursor + (frame * frameSize) + (channel * bytesPerSample));
            loudest = qMax(loudest, std::fabs(sample));
        }
        energy += static_cast<double>(loudest) * loudest;
    }

    const double rms = std::sqrt(energy / static_cast<double>(frames));
    const double decibels = rms > 0.000001 ? 20.0 * std::log10(rms) : -120.0;
    publishMicLevel(qBound(0.0, (decibels + 60.0) / 60.0, 1.0));
}

void RecorderBackend::publishMicLevel(qreal level)
{
    m_micLevel = level > m_micLevel ? level : (m_micLevel * 0.7) + (level * 0.3);
    if (level >= m_micPeak || m_micPeakAge.elapsed() > 1400) {
        m_micPeak = qMax(level, m_micLevel);
        m_micPeakAge.restart();
    }
    emit micLevelChanged();
}

void RecorderBackend::decayMicLevel()
{
    if (m_micLevel <= 0.001 && m_micPeak <= 0.001)
        return;
    m_micLevel = m_micLevel * 0.82;
    if (m_micPeakAge.elapsed() > 1400)
        m_micPeak = qMax(m_micLevel, m_micPeak * 0.9);
    if (m_micLevel < 0.002)
        m_micLevel = 0;
    if (m_micPeak < 0.002)
        m_micPeak = 0;
    emit micLevelChanged();
}

void RecorderBackend::loadMicGain()
{
    const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
    if (pactl.isEmpty())
        return;

    QProcess process;
    process.start(pactl, {QStringLiteral("get-source-volume"), pulseSourceName()});
    if (!process.waitForFinished(1200))
        return;

    static const QRegularExpression percentage(QStringLiteral("(\\d+)%"));
    const QRegularExpressionMatch match = percentage.match(
        QString::fromUtf8(process.readAllStandardOutput()));
    if (!match.hasMatch())
        return;

    const qreal gain = qBound(0.0, match.captured(1).toDouble() / 100.0, 1.5);
    if (qFuzzyCompare(gain + 1.0, m_micGain + 1.0))
        return;
    m_micGain = gain;
    emit micGainChanged();
}

QString RecorderBackend::pulseSourceName() const
{
    if (m_inputDevice.isEmpty() || m_inputDevice == QStringLiteral("default_input"))
        return QStringLiteral("@DEFAULT_SOURCE@");
    return m_inputDevice;
}

QString RecorderBackend::socketPath() const
{
    QString runtime = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtime.isEmpty())
        runtime = QDir::tempPath() + QStringLiteral("/remcorder-%1").arg(getuid());
    return QDir(runtime).filePath(QStringLiteral("remcorder/remcorder.sock"));
}

QVariantList RecorderBackend::discover(const QString &argument, bool inputs) const
{
    QProcess process;
    process.start(QStringLiteral("gpu-screen-recorder"), {argument});
    if (!process.waitForFinished(2000))
        return {};

    QVariantList result;
    const QStringList lines = QString::fromUtf8(process.readAllStandardOutput())
                                  .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const qsizetype separator = line.indexOf(QLatin1Char('|'));
        const QString value = separator >= 0 ? line.left(separator).trimmed() : line.trimmed();
        const QString detail = separator >= 0 ? line.mid(separator + 1).trimmed() : QString();
        if (value.isEmpty())
            continue;

        if (argument == QStringLiteral("--list-audio-devices")) {
            const bool isInput = value == QStringLiteral("default_input")
                || (value.contains(QStringLiteral("input")) && !value.endsWith(QStringLiteral(".monitor")));
            const bool isOutput = value == QStringLiteral("default_output") || value.endsWith(QStringLiteral(".monitor"));
            if ((inputs && !isInput) || (!inputs && !isOutput))
                continue;
        }

        QVariantMap item;
        item.insert(QStringLiteral("value"), value);
        item.insert(QStringLiteral("name"), detail.isEmpty() ? value : detail);
        item.insert(QStringLiteral("detail"), argument == QStringLiteral("--list-monitors") ? detail : value);
        result.append(item);
    }
    return result;
}
