#include "AnnotationInput.h"

#include <QDir>
#include <array>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace {
using KeyBits = std::array<unsigned char, (KEY_MAX + 8) / 8>;

bool hasKey(const KeyBits &bits, int key)
{
    return bits[key / 8] & (1 << (key % 8));
}
}

AnnotationInput::AnnotationInput(QObject *parent) : QObject(parent)
{
    m_clock.start();
    m_poll.setInterval(10);
    m_poll.setTimerType(Qt::PreciseTimer);
    m_discovery.setInterval(2000);
    connect(&m_poll, &QTimer::timeout, this, &AnnotationInput::poll);
    connect(&m_discovery, &QTimer::timeout, this, &AnnotationInput::discover);
}

AnnotationInput::~AnnotationInput()
{
    closeDevices();
}

void AnnotationInput::closeDevices()
{
    for (int fd : std::as_const(m_devices))
        ::close(fd);
    m_devices.clear();
}

void AnnotationInput::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    m_down = false;
    m_lastTap = -1000;
    setActive(false);
    if (enabled) {
        discover();
        m_poll.start();
        m_discovery.start();
    } else {
        m_poll.stop();
        m_discovery.stop();
        closeDevices();
        emit clearRequested();
    }
    emit enabledChanged();
}

void AnnotationInput::discover()
{
    const QDir directory(QStringLiteral("/dev/input"));
    for (const QString &name : directory.entryList({QStringLiteral("event*")}, QDir::System | QDir::Files)) {
        const QString path = directory.filePath(name);
        if (m_devices.contains(path))
            continue;
        const int fd = ::open(path.toLocal8Bit().constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0)
            continue;
        KeyBits bits{};
        if (::ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits.data()) >= 0
            && hasKey(bits, KEY_A) && hasKey(bits, KEY_LEFTSHIFT))
            m_devices.insert(path, fd);
        else
            ::close(fd);
    }
    const QString error = m_devices.isEmpty()
        ? QStringLiteral("Keyboard access unavailable. Join the input group, then log out and back in.")
        : QString();
    if (error != m_error) {
        m_error = error;
        emit errorChanged();
    }
}

void AnnotationInput::poll()
{
    bool down = false;
    bool chord = false;
    for (auto it = m_devices.begin(); it != m_devices.end();) {
        KeyBits bits{};
        if (::ioctl(it.value(), EVIOCGKEY(sizeof(bits)), bits.data()) < 0) {
            ::close(it.value());
            it = m_devices.erase(it);
            m_lastTap = -1000;
            m_chord = true;
            continue;
        }
        down |= hasKey(bits, KEY_LEFTSHIFT);
        for (int key = KEY_ESC; key < BTN_MISC; ++key) {
            if (key != KEY_LEFTSHIFT && hasKey(bits, key))
                chord = true;
        }
        ++it;
    }
    observeShift(down, chord);
}

void AnnotationInput::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
}

void AnnotationInput::observeShift(bool down, bool chord)
{
    const qint64 now = m_clock.elapsed();
    if (chord) {
        m_lastTap = -1000;
        setActive(false);
    }
    if (down && !m_down) {
        m_pressed = now;
        m_chord = chord;
    }
    m_chord |= chord;
    if (!down && m_down) {
        if (!m_chord && now - m_pressed < 250) {
            if (now - m_lastTap <= 350) {
                setActive(!m_active);
                m_lastTap = -1000;
            } else {
                m_lastTap = now;
            }
        } else {
            m_lastTap = -1000;
        }
    }
    m_down = down;
}
