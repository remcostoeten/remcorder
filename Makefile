PREFIX ?= $(HOME)/.local
SYSTEMD_USER_DIR ?= $(HOME)/.config/systemd/user
AUTOSTART_DIR ?= $(HOME)/.config/autostart

.PHONY: all gui check install uninstall tray tray-off

all: gui
	go build ./cmd/remcorderd ./cmd/remcorderctl

gui:
	cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
	cmake --build build

check:
	go test ./...
	go vet ./...
	cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
	cmake --build build
	qmllint app/qml/Main.qml

install: check
	install -d "$(PREFIX)/bin"
	go build -o "$(PREFIX)/bin/remcorderd" ./cmd/remcorderd
	go build -o "$(PREFIX)/bin/remcorderctl" ./cmd/remcorderctl
	install -Dm755 build/remcorder "$(PREFIX)/bin/remcorder"
	install -Dm644 overlay/main.qml "$(PREFIX)/share/remcorder/overlay/main.qml"
	install -Dm644 packaging/remcorder.desktop "$(PREFIX)/share/applications/remcorder.desktop"
	install -Dm644 packaging/remcorder.svg "$(PREFIX)/share/icons/hicolor/scalable/apps/remcorder.svg"
	install -Dm644 systemd/remcorder.service "$(SYSTEMD_USER_DIR)/remcorder.service"
	install -Dm644 systemd/remcorder-overlay.service "$(SYSTEMD_USER_DIR)/remcorder-overlay.service"
	systemctl --user daemon-reload
	systemctl --user try-restart remcorder.service remcorder-overlay.service
	command -v update-desktop-database >/dev/null && update-desktop-database "$(PREFIX)/share/applications" || true

tray: install
	install -Dm644 packaging/remcorder-tray.desktop "$(AUTOSTART_DIR)/remcorder-tray.desktop"
	pkill -x remcorder || true
	setsid "$(PREFIX)/bin/remcorder" --tray >/dev/null 2>&1 < /dev/null &

tray-off:
	rm -f "$(AUTOSTART_DIR)/remcorder-tray.desktop"
	pkill -x remcorder || true

uninstall:
	systemctl --user disable --now remcorder.service || true
	systemctl --user disable --now remcorder-overlay.service || true
	rm -f "$(PREFIX)/bin/remcorderd" "$(PREFIX)/bin/remcorderctl" "$(PREFIX)/bin/remcorder"
	rm -rf "$(PREFIX)/share/remcorder"
	rm -f "$(PREFIX)/share/applications/remcorder.desktop"
	rm -f "$(AUTOSTART_DIR)/remcorder-tray.desktop"
	rm -f "$(PREFIX)/share/icons/hicolor/scalable/apps/remcorder.svg"
	rm -f "$(SYSTEMD_USER_DIR)/remcorder.service" "$(SYSTEMD_USER_DIR)/remcorder-overlay.service"
	systemctl --user daemon-reload
