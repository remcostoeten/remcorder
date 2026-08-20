#pragma once

#include <QAudioFormat>
#include <QElapsedTimer>
#include <QObject>
#include <QJsonObject>
#include <QProcess>
#include <QSystemTrayIcon>
#include <QVariantList>

class QAction;
class QAudioSink;
class QAudioSource;
class QIODevice;
class QMenu;
class QTimer;

class RecorderBackend final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool recording READ recording NOTIFY stateChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY stateChanged)
    Q_PROPERTY(bool serviceAvailable READ serviceAvailable NOTIFY serviceAvailableChanged)
    Q_PROPERTY(bool trayAvailable READ trayAvailable CONSTANT)
    Q_PROPERTY(QString initialTrimPath READ initialTrimPath CONSTANT)
    Q_PROPERTY(bool startHidden READ startHidden CONSTANT)
    Q_PROPERTY(qint64 durationSeconds READ durationSeconds NOTIFY stateChanged)
    Q_PROPERTY(QString outputFile READ outputFile NOTIFY stateChanged)
    Q_PROPERTY(QString lastOutputFile READ lastOutputFile NOTIFY stateChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorChanged)
    Q_PROPERTY(bool processingTrim READ processingTrim NOTIFY trimStateChanged)
    Q_PROPERTY(int trimProgress READ trimProgress NOTIFY trimStateChanged)
    Q_PROPERTY(QString lastTrimmedOutputFile READ lastTrimmedOutputFile NOTIFY trimStateChanged)
    Q_PROPERTY(QVariantList monitors READ monitors NOTIFY devicesChanged)
    Q_PROPERTY(QVariantList outputDevices READ outputDevices NOTIFY devicesChanged)
    Q_PROPERTY(QVariantList inputDevices READ inputDevices NOTIFY devicesChanged)

    Q_PROPERTY(QString captureSource READ captureSource WRITE setCaptureSource NOTIFY settingsChanged)
    Q_PROPERTY(QString captureRegion READ captureRegion NOTIFY settingsChanged)
    Q_PROPERTY(QString captureRegionLabel READ captureRegionLabel NOTIFY settingsChanged)
    Q_PROPERTY(bool desktopAudioEnabled READ desktopAudioEnabled WRITE setDesktopAudioEnabled NOTIFY settingsChanged)
    Q_PROPERTY(bool microphoneEnabled READ microphoneEnabled WRITE setMicrophoneEnabled NOTIFY settingsChanged)
    Q_PROPERTY(QString outputDevice READ outputDevice WRITE setOutputDevice NOTIFY settingsChanged)
    Q_PROPERTY(QString inputDevice READ inputDevice WRITE setInputDevice NOTIFY settingsChanged)
    Q_PROPERTY(QString qualityPreset READ qualityPreset WRITE setQualityPreset NOTIFY settingsChanged)
    Q_PROPERTY(QString outputDirectory READ outputDirectory WRITE setOutputDirectory NOTIFY settingsChanged)
    Q_PROPERTY(bool captureCursor READ captureCursor WRITE setCaptureCursor NOTIFY settingsChanged)
    Q_PROPERTY(bool soundCuesEnabled READ soundCuesEnabled WRITE setSoundCuesEnabled NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList recentRecordings READ recentRecordings NOTIFY recentRecordingsChanged)

    Q_PROPERTY(bool micMonitorEnabled READ micMonitorEnabled WRITE setMicMonitorEnabled NOTIFY micMonitorChanged)
    Q_PROPERTY(bool micMonitorActive READ micMonitorActive NOTIFY micMonitorChanged)
    Q_PROPERTY(bool micPlaybackEnabled READ micPlaybackEnabled WRITE setMicPlaybackEnabled NOTIFY micMonitorChanged)
    Q_PROPERTY(QString micDeviceName READ micDeviceName NOTIFY micMonitorChanged)
    Q_PROPERTY(qreal micLevel READ micLevel NOTIFY micLevelChanged)
    Q_PROPERTY(qreal micPeak READ micPeak NOTIFY micLevelChanged)
    Q_PROPERTY(qreal micGain READ micGain WRITE setMicGain NOTIFY micGainChanged)
    Q_PROPERTY(bool micGainSupported READ micGainSupported CONSTANT)

public:
    explicit RecorderBackend(QObject *parent = nullptr);
    ~RecorderBackend() override;

    bool recording() const { return m_recording; }
    bool paused() const { return m_paused; }
    bool serviceAvailable() const { return m_serviceAvailable; }
    bool trayAvailable() const;
    QString initialTrimPath() const { return m_initialTrimPath; }
    bool startHidden() const { return m_startHidden; }
    qint64 durationSeconds() const { return m_durationSeconds; }
    QString outputFile() const { return m_outputFile; }
    QString lastOutputFile() const { return m_lastOutputFile; }
    QString errorMessage() const { return m_errorMessage; }
    bool processingTrim() const { return m_processingTrim; }
    int trimProgress() const { return m_trimProgress; }
    QString lastTrimmedOutputFile() const { return m_lastTrimmedOutputFile; }
    QVariantList monitors() const { return m_monitors; }
    QVariantList outputDevices() const { return m_outputDevices; }
    QVariantList inputDevices() const { return m_inputDevices; }

    QString captureSource() const { return m_captureSource; }
    QString captureRegion() const { return m_captureRegion; }
    QString captureRegionLabel() const;
    bool desktopAudioEnabled() const { return m_desktopAudioEnabled; }
    bool microphoneEnabled() const { return m_microphoneEnabled; }
    QString outputDevice() const { return m_outputDevice; }
    QString inputDevice() const { return m_inputDevice; }
    QString qualityPreset() const { return m_qualityPreset; }
    QString outputDirectory() const { return m_outputDirectory; }
    bool captureCursor() const { return m_captureCursor; }
    bool soundCuesEnabled() const { return m_soundCuesEnabled; }
    QVariantList recentRecordings() const { return m_recentRecordings; }

    bool micMonitorEnabled() const { return m_micMonitorEnabled; }
    bool micMonitorActive() const { return m_micSource != nullptr; }
    bool micPlaybackEnabled() const { return m_micPlaybackEnabled; }
    QString micDeviceName() const { return m_micDeviceName; }
    qreal micLevel() const { return m_micLevel; }
    qreal micPeak() const { return m_micPeak; }
    qreal micGain() const { return m_micGain; }
    bool micGainSupported() const;

    void setCaptureSource(const QString &value);
    void setDesktopAudioEnabled(bool value);
    void setMicrophoneEnabled(bool value);
    void setOutputDevice(const QString &value);
    void setInputDevice(const QString &value);
    void setQualityPreset(const QString &value);
    void setOutputDirectory(const QString &value);
    void setCaptureCursor(bool value);
    void setSoundCuesEnabled(bool value);
    void setMicMonitorEnabled(bool value);
    void setMicPlaybackEnabled(bool value);
    void setMicGain(qreal value);

    Q_INVOKABLE void setCaptureRegionFromRect(qreal x,
                                             qreal y,
                                             qreal width,
                                             qreal height,
                                             qreal devicePixelRatio);
    Q_INVOKABLE void clearCaptureRegion();
    Q_INVOKABLE void startRecording();
    Q_INVOKABLE void stopRecording();
    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void refreshState();
    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE void startService();
    Q_INVOKABLE void chooseOutputDirectory();
    Q_INVOKABLE void openOutputDirectory();
    Q_INVOKABLE void openLastRecording();
    Q_INVOKABLE QString chooseVideoToTrim();
    Q_INVOKABLE void exportTrim(const QString &source,
                                double startSeconds,
                                double endSeconds,
                                bool motionBlur,
                                const QString &motionBlurStrength);
    Q_INVOKABLE void openLastTrimmedRecording();
    Q_INVOKABLE QString formatDuration(qint64 seconds) const;
    Q_INVOKABLE void copyLastOutputPath();
    Q_INVOKABLE void openRecentRecording(const QString &path);

signals:
    void stateChanged();
    void serviceAvailableChanged();
    void devicesChanged();
    void settingsChanged();
    void errorChanged();
    void trimStateChanged();
    void micMonitorChanged();
    void micLevelChanged();
    void micGainChanged();
    void recentRecordingsChanged();
    void requestShow();

private:
    bool request(const QJsonObject &payload,
                 QJsonObject *response,
                 bool showTransportError,
                 int timeoutMilliseconds = 1200);
    void applyResponse(const QJsonObject &response);
    void setError(const QString &message);
    void setServiceAvailable(bool available);
    void loadSettings();
    void saveSetting(const QString &key, const QVariant &value);
    void setupTray();
    void updateTray();
    void updateRecentMenu();
    void notifyTray(const QString &title, const QString &path);
    void rememberRecentRecording(const QString &path);
    void playStartCue();
    void playStopCue();
    void updateTrimProgress();
    void finishTrim(int exitCode, QProcess::ExitStatus status);
    QString trimOutputPath(const QString &source, bool motionBlur) const;
    QStringList videoEncoderOptions(QString *encoder) const;
    QString socketPath() const;
    QVariantList discover(const QString &argument, bool inputs) const;
    void syncMicMonitor();
    void startMicMonitor();
    void stopMicMonitor();
    void readMicSamples();
    void decayMicLevel();
    void publishMicLevel(qreal level);
    void loadMicGain();
    QString pulseSourceName() const;

    bool m_recording = false;
    bool m_paused = false;
    bool m_serviceAvailable = false;
    qint64 m_durationSeconds = 0;
    QString m_outputFile;
    QString m_lastOutputFile;
    QString m_errorMessage;
    QString m_initialTrimPath;
    bool m_startHidden = false;
    bool m_processingTrim = false;
    int m_trimProgress = 0;
    QString m_lastTrimmedOutputFile;
    QString m_trimOutputFile;
    QString m_trimTemporaryFile;
    qint64 m_trimDurationMilliseconds = 0;
    QByteArray m_trimProgressBuffer;
    QVariantList m_monitors;
    QVariantList m_outputDevices;
    QVariantList m_inputDevices;

    QString m_captureSource = QStringLiteral("screen");
    QString m_captureRegion;
    bool m_desktopAudioEnabled = true;
    bool m_microphoneEnabled = false;
    QString m_outputDevice = QStringLiteral("default_output");
    QString m_inputDevice = QStringLiteral("default_input");
    QString m_qualityPreset = QStringLiteral("balanced");
    QString m_outputDirectory;
    bool m_captureCursor = true;
    QString m_activeCodec = QStringLiteral("h264");
    bool m_soundCuesEnabled = true;
    QVariantList m_recentRecordings;
    QString m_lastNotificationPath;

    bool m_requestInFlight = false;

    bool m_micMonitorEnabled = false;
    bool m_micPlaybackEnabled = false;
    qreal m_micLevel = 0;
    qreal m_micPeak = 0;
    qreal m_micGain = 1.0;
    QString m_micDeviceName;
    QAudioFormat m_micFormat;
    QAudioSource *m_micSource = nullptr;
    QIODevice *m_micStream = nullptr;
    QAudioSink *m_micSink = nullptr;
    QIODevice *m_micSinkStream = nullptr;
    QTimer *m_micDecayTimer = nullptr;
    QElapsedTimer m_micPeakAge;

    QTimer *m_pollTimer = nullptr;
    QSystemTrayIcon *m_tray = nullptr;
    QMenu *m_trayMenu = nullptr;
    QAction *m_showAction = nullptr;
    QAction *m_recordAction = nullptr;
    QAction *m_pauseAction = nullptr;
    QAction *m_stopAction = nullptr;
    QAction *m_openAction = nullptr;
    QAction *m_openTrimAction = nullptr;
    QAction *m_copyPathAction = nullptr;
    QMenu *m_recentMenu = nullptr;
    QAction *m_quitAction = nullptr;
    QProcess *m_trimProcess = nullptr;
};
