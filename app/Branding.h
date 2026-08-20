#pragma once

#include <QIcon>
#include <QString>
#include <initializer_list>

namespace branding {

/**
 * Multi-size application icon from the embedded brand assets, for the window
 * and taskbar. Falls back to the installed hicolor theme icon when the
 * resources are unavailable.
 */
inline QIcon applicationIcon()
{
    QIcon icon;
    for (int size : {16, 24, 32, 48, 64, 128, 256, 512})
        icon.addFile(QStringLiteral(":/branding/remcorder-%1.png").arg(size));
    if (icon.isNull())
        return QIcon::fromTheme(QStringLiteral("remcorder"));
    return icon;
}

/**
 * Tray variant of the mark, exported at the small sizes panels ask for so the
 * symbol stays legible instead of being downscaled from the app icon.
 */
inline QIcon trayIcon()
{
    QIcon icon;
    for (int size : {16, 22, 24, 32, 48, 64})
        icon.addFile(QStringLiteral(":/branding/tray/remcorder-tray-%1.png").arg(size));
    if (icon.isNull())
        return applicationIcon();
    return icon;
}

}
