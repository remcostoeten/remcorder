cmake_minimum_required(VERSION 3.21)

project(Remcorder VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    DBus
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

# Wayland compositors ignore Qt::WindowStaysOnTopHint; LayerShellQt keeps the
# recording pill and keystroke strip above everything via wlr-layer-shell.
find_package(LayerShellQt QUIET)

qt_add_executable(remcorder
    app/AnnotationInput.cpp
    app/AnnotationInput.h
    app/AnnotationCanvas.cpp
    app/AnnotationCanvas.h
    app/main.cpp
    app/Branding.h
    app/RecorderBackend.cpp
    app/RecorderBackend.h
    app/SingleInstance.cpp
    app/SingleInstance.h
    app/TrimPreview.cpp
    app/TrimPreview.h
    app/WindowChrome.cpp
    app/WindowChrome.h
)

set_source_files_properties(app/qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(remcorder
    URI Remcorder
    VERSION 1.0
    # The import scan walks the whole source tree and trips over overlay/*.qml,
    # whose org.kde.layershell import has no CMake target to link. It only
    # matters for static Qt builds, which this project does not do.
    NO_IMPORT_SCAN
    QML_FILES
        app/qml/AnnotationTools.qml
        app/qml/Theme.qml
        app/qml/Glyph.qml
        app/qml/Card.qml
        app/qml/FocusRing.qml
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
        app/qml/WebcamWindow.qml
        app/qml/KeystrokeStrip.qml
        app/qml/KeystrokeWindow.qml
        app/qml/LibrarySheet.qml
        app/qml/SavedRecordingCard.qml
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

target_include_directories(remcorder PRIVATE app)

target_link_libraries(remcorder PRIVATE
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::Multimedia
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
)

if(LayerShellQt_FOUND)
    target_compile_definitions(remcorder PRIVATE REMCORDER_HAVE_LAYERSHELLQT)
    target_link_libraries(remcorder PRIVATE LayerShellQt::Interface)
    message(STATUS "LayerShellQt found: overlays pinned above other windows on Wayland")
else()
    message(STATUS "LayerShellQt not found: overlays rely on Qt::WindowStaysOnTopHint (X11 only)")
endif()

target_compile_options(remcorder PRIVATE
    -Wall
    -Wextra
    -Wpedantic
)

install(TARGETS remcorder
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)

option(REMCORDER_BUILD_TESTS "Build annotation tests" OFF)
if(REMCORDER_BUILD_TESTS)
    enable_testing()
    find_package(Qt6 REQUIRED COMPONENTS Test)
    qt_add_executable(annotation-tests
        tests/annotations.cpp
        app/AnnotationInput.cpp app/AnnotationInput.h
        app/AnnotationCanvas.cpp app/AnnotationCanvas.h
        app/WindowChrome.cpp app/WindowChrome.h
    )
    qt_add_qml_module(annotation-tests
        URI AnnotationTests
        VERSION 1.0
        NO_IMPORT_SCAN
        QML_FILES app/qml/AnnotationTools.qml app/qml/Theme.qml
    )
    target_include_directories(annotation-tests PRIVATE app)
    target_link_libraries(annotation-tests PRIVATE Qt6::Test Qt6::Quick)
    add_test(NAME annotations COMMAND annotation-tests)
    set_tests_properties(annotations PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
