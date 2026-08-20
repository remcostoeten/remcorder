PREFIX ?= $(HOME)/.local
SYSTEMD_USER_DIR ?= $(HOME)/.config/systemd/user
AUTOSTART_DIR ?= $(HOME)/.config/autostart
ICON_SIZES := 16 24 32 48 64 128 256 512

.PHONY: all gui check install uninstall tray tray-off

all: gui
	go build -o remcorderd ./cmd/remcorderd
	go build -o remcorderctl ./cmd/remcorderctl

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
	install -Dm755 scripts/remcorder-overlay "$(PREFIX)/bin/remcorder-overlay"
	install -Dm644 overlay/main.qml "$(PREFIX)/share/remcorder/overlay/main.qml"
	install -Dm644 packaging/remcorder.desktop "$(PREFIX)/share/applications/remcorder.desktop"
	for size in $(ICON_SIZES); do \
		install -Dm644 "packaging/icons/remcorder-$$size.png" \
			"$(PREFIX)/share/icons/hicolor/$${size}x$${size}/apps/remcorder.png"; \
	done
	install -Dm644 systemd/remcorder.service "$(SYSTEMD_USER_DIR)/remcorder.service"
	install -Dm644 systemd/remcorder-overlay.service "$(SYSTEMD_USER_DIR)/remcorder-overlay.service"
	systemctl --user daemon-reload
	systemctl --user try-restart remcorder.service remcorder-overlay.service
	command -v update-desktop-database >/dev/null && update-desktop-database "$(PREFIX)/share/applications" || true
	command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t -f "$(PREFIX)/share/icons/hicolor" || true

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
	rm -f "$(PREFIX)/bin/remcorderd" "$(PREFIX)/bin/remcorderctl" "$(PREFIX)/bin/remcorder" "$(PREFIX)/bin/remcorder-overlay"
	rm -rf "$(PREFIX)/share/remcorder"
	rm -f "$(PREFIX)/share/applications/remcorder.desktop"
	rm -f "$(AUTOSTART_DIR)/remcorder-tray.desktop"
	for size in $(ICON_SIZES); do \
		rm -f "$(PREFIX)/share/icons/hicolor/$${size}x$${size}/apps/remcorder.png"; \
	done
	rm -f "$(SYSTEMD_USER_DIR)/remcorder.service" "$(SYSTEMD_USER_DIR)/remcorder-overlay.service"
	systemctl --user daemon-reload
