cmake_minimum_required(VERSION 3.21)

project(Remcorder VERSION 0.0.7 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Gui
    Multimedia
    Network
    Qml
    Quick
    QuickControls2
    Widgets
)

qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0004 NEW)

qt_add_executable(remcorder
    app/main.cpp
    app/Branding.h
    app/RecorderBackend.cpp
    app/RecorderBackend.h
    app/TrimPreview.cpp
    app/TrimPreview.h
    app/WindowChrome.h
)

set_source_files_properties(app/qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(remcorder
    URI Remcorder
    VERSION 1.0
    QML_FILES
        app/qml/Theme.qml
        app/qml/Glyph.qml
        app/qml/Card.qml
        app/qml/Chip.qml
        app/qml/Popover.qml
        app/qml/GhostButton.qml
        app/qml/PrimaryButton.qml
        app/qml/WindowButton.qml
        app/qml/PillButton.qml
        app/qml/Segmented.qml
        app/qml/ModernSwitch.qml
        app/qml/DeviceCombo.qml
        app/qml/LevelMeter.qml
        app/qml/RecordingPill.qml
        app/qml/LibrarySheet.qml
        app/qml/TrimWindow.qml
        app/qml/Main.qml
        app/qml/RegionSelector.qml
)

qt_add_resources(remcorder "branding"
    PREFIX /branding
    BASE packaging/icons
    FILES
        packaging/icons/remcorder-16.png
        packaging/icons/remcorder-24.png
        packaging/icons/remcorder-32.png
        packaging/icons/remcorder-48.png
        packaging/icons/remcorder-64.png
        packaging/icons/remcorder-128.png
        packaging/icons/remcorder-256.png
        packaging/icons/remcorder-512.png
        packaging/icons/tray/remcorder-tray-16.png
        packaging/icons/tray/remcorder-tray-22.png
        packaging/icons/tray/remcorder-tray-24.png
        packaging/icons/tray/remcorder-tray-32.png
        packaging/icons/tray/remcorder-tray-48.png
        packaging/icons/tray/remcorder-tray-64.png
)

target_link_libraries(remcorder PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Multimedia
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
)

target_compile_options(remcorder PRIVATE
    -Wall
    -Wextra
    -Wpedantic
)

install(TARGETS remcorder
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)
