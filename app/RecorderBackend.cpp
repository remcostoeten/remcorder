#include "RecorderBackend.h"

#include <QAction>
#include <QApplication>
#include <QAudioDevice>
#include <QAudioSink>
#include <QAudioSource>
#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileDialog>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QMediaDevices>
#include <QMenu>
#include <QPainter>
#include <QProcess>
#include <QRegularExpression>
#include <QScopeGuard>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <unistd.h>

#include <cmath>

namespace {
constexpr auto organization = "RemcoStoeten";
constexpr auto application = "Remcorder";

QIcon recorderIcon()
{
    QPixmap pixmap(64, 64);
    pixmap.fill(Qt::transparent);
    QPainter painter(&pixmap);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setPen(QPen(QColor("#FF6575"), 4));
    painter.setBrush(QColor("#FF4054"));
    painter.drawEllipse(QRectF(9, 9, 46, 46));
    painter.setPen(Qt::NoPen);
    painter.setBrush(QColor("#151923"));
    painter.drawEllipse(QRectF(22, 22, 20, 20));
    return QIcon(pixmap);
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
    stopMicMonitor();
    if (m_blurProcess && m_blurProcess->state() != QProcess::NotRunning) {
        m_blurProcess->terminate();
        if (!m_blurProcess->waitForFinished(1500)) {
            m_blurProcess->kill();
            m_blurProcess->waitForFinished(500);
        }
    }
    if (!m_blurTemporaryFile.isEmpty())
        QFile::remove(m_blurTemporaryFile);
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

void RecorderBackend::setMotionBlurEnabled(bool value)
{
    if (value == m_motionBlurEnabled)
        return;
    m_motionBlurEnabled = value;
    saveSetting(QStringLiteral("motionBlurEnabled"), value);
    emit settingsChanged();
}

void RecorderBackend::setMotionBlurStrength(const QString &value)
{
    if ((value != QStringLiteral("subtle")
         && value != QStringLiteral("smooth")
         && value != QStringLiteral("strong"))
        || value == m_motionBlurStrength) {
        return;
    }
    m_motionBlurStrength = value;
    saveSetting(QStringLiteral("motionBlurStrength"), value);
    emit settingsChanged();
}

void RecorderBackend::startRecording()
{
    if (m_processingBlur || m_processingTrim) {
        setError(QStringLiteral("Wait for post-processing to finish before starting another recording."));
        return;
    }
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
    };
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
    QJsonObject response;
    if (request({{QStringLiteral("action"), QStringLiteral("stop")}}, &response, true, 13000))
        applyResponse(response);
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

void RecorderBackend::openLastBlurredRecording()
{
    if (!m_lastBlurredOutputFile.isEmpty())
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_lastBlurredOutputFile));
}

QString RecorderBackend::chooseVideoToTrim()
{
    return QFileDialog::getOpenFileName(
        nullptr,
        QStringLiteral("Choose a recording to trim"),
        m_outputDirectory,
        QStringLiteral("Video files (*.mp4 *.mkv *.webm *.mov);;All files (*)"));
}

void RecorderBackend::exportTrim(const QString &source, double startSeconds, double endSeconds)
{
    if (m_recording || m_processingBlur || m_processingTrim) {
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

    m_trimOutputFile = trimOutputPath(source);
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
        QStringLiteral("-map"), QStringLiteral("0:v:0"),
        QStringLiteral("-map"), QStringLiteral("0:a?"),
        QStringLiteral("-c:v"), encoder,
    };
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
    const qint64 completedDuration = m_durationSeconds;
    const QString previousLast = m_lastOutputFile;

    m_recording = state.value(QStringLiteral("recording")).toBool();
    m_paused = state.value(QStringLiteral("paused")).toBool();
    m_durationSeconds = state.value(QStringLiteral("duration_seconds")).toInteger();
    m_outputFile = state.value(QStringLiteral("output_file")).toString();
    m_lastOutputFile = state.value(QStringLiteral("last_output_file")).toString();

    const QString stateError = state.value(QStringLiteral("last_error")).toString();
    if (!stateError.isEmpty())
        setError(stateError);

    emit stateChanged();
    updateTray();

    if (!wasRecording && m_recording)
        setMicPlaybackEnabled(false);

    if (wasRecording && !m_recording && !m_lastOutputFile.isEmpty()
        && m_lastOutputFile != previousLast && m_tray) {
        m_tray->showMessage(QStringLiteral("Recording saved"),
                            QFileInfo(m_lastOutputFile).fileName(),
                            QSystemTrayIcon::Information, 5000);
    }
    if (wasRecording && !m_recording && !m_lastOutputFile.isEmpty()
        && m_lastOutputFile != previousLast && m_motionBlurEnabled) {
        startMotionBlur(m_lastOutputFile, completedDuration);
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
    m_desktopAudioEnabled = settings.value(QStringLiteral("desktopAudioEnabled"), true).toBool();
    m_microphoneEnabled = settings.value(QStringLiteral("microphoneEnabled"), false).toBool();
    m_outputDevice = settings.value(QStringLiteral("outputDevice"), QStringLiteral("default_output")).toString();
    m_inputDevice = settings.value(QStringLiteral("inputDevice"), QStringLiteral("default_input")).toString();
    m_qualityPreset = settings.value(QStringLiteral("qualityPreset"), QStringLiteral("balanced")).toString();
    m_captureCursor = settings.value(QStringLiteral("captureCursor"), true).toBool();
    m_motionBlurEnabled = settings.value(QStringLiteral("motionBlurEnabled"), false).toBool();
    m_motionBlurStrength = settings.value(
        QStringLiteral("motionBlurStrength"), QStringLiteral("smooth")).toString();
    if (m_motionBlurStrength != QStringLiteral("subtle")
        && m_motionBlurStrength != QStringLiteral("smooth")
        && m_motionBlurStrength != QStringLiteral("strong")) {
        m_motionBlurStrength = QStringLiteral("smooth");
    }
    m_lastBlurredOutputFile = settings.value(
        QStringLiteral("lastBlurredOutputFile")).toString();
    if (!QFileInfo::exists(m_lastBlurredOutputFile))
        m_lastBlurredOutputFile.clear();
    m_lastTrimmedOutputFile = settings.value(
        QStringLiteral("lastTrimmedOutputFile")).toString();
    if (!QFileInfo::exists(m_lastTrimmedOutputFile))
        m_lastTrimmedOutputFile.clear();

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

    m_tray = new QSystemTrayIcon(recorderIcon(), this);
    m_trayMenu = new QMenu;
    m_showAction = m_trayMenu->addAction(QStringLiteral("Open Remcorder"));
    m_trayMenu->addSeparator();
    m_recordAction = m_trayMenu->addAction(QStringLiteral("Start recording"));
    m_pauseAction = m_trayMenu->addAction(QStringLiteral("Pause"));
    m_stopAction = m_trayMenu->addAction(QStringLiteral("Stop and save"));
    m_trayMenu->addSeparator();
    m_openAction = m_trayMenu->addAction(QStringLiteral("Open recordings folder"));
    m_openBlurAction = m_trayMenu->addAction(QStringLiteral("Open last blurred copy"));
    m_openTrimAction = m_trayMenu->addAction(QStringLiteral("Open last trimmed copy"));
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
    connect(m_openAction, &QAction::triggered, this, &RecorderBackend::openOutputDirectory);
    connect(m_openBlurAction, &QAction::triggered,
            this, &RecorderBackend::openLastBlurredRecording);
    connect(m_openTrimAction, &QAction::triggered,
            this, &RecorderBackend::openLastTrimmedRecording);
    connect(m_quitAction, &QAction::triggered, qApp, &QCoreApplication::quit);
    connect(m_tray, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick)
            emit requestShow();
    });

    m_tray->setContextMenu(m_trayMenu);
    m_tray->setToolTip(QStringLiteral("Remcorder"));
    m_tray->show();
    updateTray();
}

void RecorderBackend::updateTray()
{
    if (!m_tray)
        return;
    const bool processing = m_processingBlur || m_processingTrim;
    m_recordAction->setEnabled(m_serviceAvailable && !m_recording && !processing);
    m_pauseAction->setEnabled(m_serviceAvailable && m_recording);
    m_pauseAction->setText(m_paused ? QStringLiteral("Resume") : QStringLiteral("Pause"));
    m_stopAction->setEnabled(m_serviceAvailable && m_recording);
    m_openBlurAction->setEnabled(!m_lastBlurredOutputFile.isEmpty() && !processing);
    m_openTrimAction->setEnabled(!m_lastTrimmedOutputFile.isEmpty() && !processing);
    m_quitAction->setEnabled(!processing);
    if (m_processingTrim) {
        m_tray->setToolTip(QStringLiteral("Exporting trim · %1%").arg(m_trimProgress));
    } else if (m_processingBlur) {
        m_tray->setToolTip(QStringLiteral("Creating motion blur · %1%").arg(m_blurProgress));
    } else if (m_recording) {
        m_tray->setToolTip(QStringLiteral("%1 · %2")
                               .arg(m_paused ? QStringLiteral("Paused") : QStringLiteral("Recording"),
                                    formatDuration(m_durationSeconds)));
    } else {
        m_tray->setToolTip(QStringLiteral("Remcorder · Ready"));
    }
}

void RecorderBackend::startMotionBlur(const QString &source, qint64 durationSeconds)
{
    if (m_processingBlur || !QFileInfo::exists(source))
        return;

    const QString ffmpeg = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    if (ffmpeg.isEmpty()) {
        setError(QStringLiteral("The original was saved, but FFmpeg is unavailable for the blurred copy."));
        return;
    }

    m_blurOutputFile = motionBlurOutputPath(source);
    const QFileInfo outputInfo(m_blurOutputFile);
    m_blurTemporaryFile = outputInfo.dir().filePath(
        QStringLiteral(".%1.partial.mp4").arg(outputInfo.completeBaseName()));
    QFile::remove(m_blurTemporaryFile);

    QString encoder;
    const QStringList encoderOptions = videoEncoderOptions(&encoder);

    const int frames = motionBlurFrames();
    QStringList weights;
    for (int index = 1; index <= frames; ++index)
        weights.append(QString::number(index));
    const QString filter = QStringLiteral("tmix=frames=%1:weights=%2")
                               .arg(frames).arg(weights.join(QLatin1Char(' ')));

    QStringList arguments{
        QStringLiteral("-hide_banner"),
        QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-nostdin"),
        QStringLiteral("-y"),
        QStringLiteral("-i"), source,
        QStringLiteral("-vf"), filter,
        QStringLiteral("-map"), QStringLiteral("0:v:0"),
        QStringLiteral("-map"), QStringLiteral("0:a?"),
        QStringLiteral("-c:v"), encoder,
    };
    arguments.append(encoderOptions);
    arguments.append({
        QStringLiteral("-c:a"), QStringLiteral("copy"),
        QStringLiteral("-movflags"), QStringLiteral("+faststart"),
        QStringLiteral("-progress"), QStringLiteral("pipe:1"),
        QStringLiteral("-nostats"),
        m_blurTemporaryFile,
    });

    m_blurDurationSeconds = qMax<qint64>(1, durationSeconds);
    m_blurProgress = 0;
    m_blurProgressBuffer.clear();
    m_processingBlur = true;
    m_blurProcess = new QProcess(this);
    m_blurProcess->setProcessChannelMode(QProcess::SeparateChannels);
    connect(m_blurProcess, &QProcess::readyReadStandardOutput,
            this, &RecorderBackend::updateBlurProgress);
    connect(m_blurProcess, &QProcess::finished,
            this, &RecorderBackend::finishMotionBlur);
    m_blurProcess->start(ffmpeg, arguments);
    if (!m_blurProcess->waitForStarted(1500)) {
        setError(QStringLiteral("The original was saved, but motion-blur processing could not start."));
        m_blurProcess->deleteLater();
        m_blurProcess = nullptr;
        m_processingBlur = false;
    }
    emit blurStateChanged();
    updateTray();
}

void RecorderBackend::updateBlurProgress()
{
    if (!m_blurProcess)
        return;
    m_blurProgressBuffer += m_blurProcess->readAllStandardOutput();

    qsizetype newline = -1;
    while ((newline = m_blurProgressBuffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_blurProgressBuffer.left(newline).trimmed();
        m_blurProgressBuffer.remove(0, newline + 1);
        if (!line.startsWith("out_time_us="))
            continue;
        bool ok = false;
        const qint64 microseconds = line.mid(sizeof("out_time_us=") - 1).toLongLong(&ok);
        if (!ok)
            continue;
        const int progress = qBound(0,
            static_cast<int>(microseconds / (m_blurDurationSeconds * 10000)), 99);
        if (progress != m_blurProgress) {
            m_blurProgress = progress;
            emit blurStateChanged();
            updateTray();
        }
    }
}

void RecorderBackend::finishMotionBlur(int exitCode, QProcess::ExitStatus status)
{
    if (!m_blurProcess)
        return;

    const QString processError = QString::fromUtf8(m_blurProcess->readAllStandardError()).trimmed();
    const bool encoded = status == QProcess::NormalExit && exitCode == 0
        && QFileInfo(m_blurTemporaryFile).size() > 0;
    bool saved = false;
    if (encoded)
        saved = QFile::rename(m_blurTemporaryFile, m_blurOutputFile);

    if (saved) {
        m_lastBlurredOutputFile = m_blurOutputFile;
        saveSetting(QStringLiteral("lastBlurredOutputFile"), m_lastBlurredOutputFile);
        m_blurProgress = 100;
        setError({});
        if (m_tray) {
            m_tray->showMessage(
                QStringLiteral("Blurred copy ready"),
                QFileInfo(m_blurOutputFile).fileName(),
                QSystemTrayIcon::Information, 6000);
        }
    } else {
        QFile::remove(m_blurTemporaryFile);
        const QString detail = processError.isEmpty()
            ? QStringLiteral("The video encoder could not create the blurred copy.")
            : processError.section(QLatin1Char('\n'), -1);
        setError(QStringLiteral("The original is safe. Motion blur failed: %1").arg(detail));
    }

    m_blurProcess->deleteLater();
    m_blurProcess = nullptr;
    m_processingBlur = false;
    emit blurStateChanged();
    updateTray();
}

QString RecorderBackend::motionBlurOutputPath(const QString &source) const
{
    const QFileInfo sourceInfo(source);
    const QString stem = sourceInfo.completeBaseName() + QStringLiteral("-blur");
    QString candidate = sourceInfo.dir().filePath(stem + QStringLiteral(".mp4"));
    int suffix = 2;
    while (QFileInfo::exists(candidate)) {
        candidate = sourceInfo.dir().filePath(
            QStringLiteral("%1-%2.mp4").arg(stem).arg(suffix++));
    }
    return candidate;
}

int RecorderBackend::motionBlurFrames() const
{
    if (m_motionBlurStrength == QStringLiteral("subtle"))
        return 2;
    if (m_motionBlurStrength == QStringLiteral("strong"))
        return 5;
    return 3;
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
            m_tray->showMessage(
                QStringLiteral("Trimmed copy ready"),
                QFileInfo(m_trimOutputFile).fileName(),
                QSystemTrayIcon::Information, 6000);
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

QString RecorderBackend::trimOutputPath(const QString &source) const
{
    const QFileInfo sourceInfo(source);
    const QString stem = sourceInfo.completeBaseName() + QStringLiteral("-trim");
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
    return QDir(runtime).filePath(QStringLiteral("remcorder/recorder.sock"));
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
