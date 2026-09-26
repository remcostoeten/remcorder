PREFIX ?= $(HOME)/.local
SYSTEMD_USER_DIR ?= $(HOME)/.config/systemd/user
AUTOSTART_DIR ?= $(HOME)/.config/autostart
ICON_SIZES := 16 24 32 48 64 128 256 512
STEP = @printf '\n\033[34m==>\033[0m \033[1m%s\033[0m\n'
QMLLINT ?= $(firstword $(shell command -v qmllint6 qmllint-qt6 qmllint 2>/dev/null) $(wildcard /usr/lib/qt6/bin/qmllint /usr/lib64/qt6/bin/qmllint) qmllint)

.PHONY: all gui check install uninstall tray tray-off help

all: gui ## Build the GUI, daemon, and CLI
	go build -o remcorderd ./cmd/remcorderd
	go build -o remcorderctl ./cmd/remcorderctl

gui: ## Build the Qt GUI only
	cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
	cmake --build build

check: ## Run Go tests/vet, build the GUI, and lint QML
	$(STEP) "Testing Go packages"
	@go test ./...
	@go vet ./...
	$(STEP) "Building the GUI"
	@cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
	@cmake --build build
	$(STEP) "Linting QML"
	@$(QMLLINT) app/qml/Main.qml app/qml/RegionSelector.qml
	@$(QMLLINT) overlay/main.qml overlay/KeystrokeOverlay.qml

install: check ## Run checks, then install binaries, assets, and user services to PREFIX
	$(STEP) "Installing to $(PREFIX)"
	@install -d "$(PREFIX)/bin"
	@go build -o "$(PREFIX)/bin/remcorderd" ./cmd/remcorderd
	@go build -o "$(PREFIX)/bin/remcorderctl" ./cmd/remcorderctl
	@install -Dm755 build/remcorder "$(PREFIX)/bin/remcorder"
	@install -Dm755 scripts/remcorder-overlay "$(PREFIX)/bin/remcorder-overlay"
	@install -Dm644 overlay/main.qml "$(PREFIX)/share/remcorder/overlay/main.qml"
	@install -Dm644 overlay/KeystrokeOverlay.qml "$(PREFIX)/share/remcorder/overlay/KeystrokeOverlay.qml"
	@install -Dm644 packaging/kwin/remcorder-overlay.kwinrule "$(PREFIX)/share/remcorder/kwin/remcorder-overlay.kwinrule"
	@install -Dm644 packaging/remcorder.desktop "$(PREFIX)/share/applications/remcorder.desktop"
	@for size in $(ICON_SIZES); do \
		install -Dm644 "packaging/icons/remcorder-$$size.png" \
			"$(PREFIX)/share/icons/hicolor/$${size}x$${size}/apps/remcorder.png"; \
	done
	@install -Dm644 systemd/remcorder.service "$(SYSTEMD_USER_DIR)/remcorder.service"
	@install -Dm644 systemd/remcorder-overlay.service "$(SYSTEMD_USER_DIR)/remcorder-overlay.service"
	$(STEP) "Reloading user services"
	@systemctl --user daemon-reload
	@systemctl --user try-restart remcorder.service remcorder-overlay.service
	@command -v update-desktop-database >/dev/null && update-desktop-database "$(PREFIX)/share/applications" || true
	@command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t -f "$(PREFIX)/share/icons/hicolor" || true
	@scripts/install-summary.sh "$(PREFIX)"

tray: install ## Install and autostart the tray app
	install -Dm644 packaging/remcorder-tray.desktop "$(AUTOSTART_DIR)/remcorder-tray.desktop"
	pkill -x remcorder || true
	setsid "$(PREFIX)/bin/remcorder" --tray >/dev/null 2>&1 < /dev/null &

tray-off: ## Disable tray autostart and stop the tray app
	rm -f "$(AUTOSTART_DIR)/remcorder-tray.desktop"
	pkill -x remcorder || true

uninstall: ## Remove everything installed by install/tray
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

help: ## Show this help
	@echo "Usage: make [target] [PREFIX=dir]"
	@echo
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Variables:"
	@echo "  PREFIX            $(PREFIX)"
	@echo "  SYSTEMD_USER_DIR  $(SYSTEMD_USER_DIR)"
	@echo "  AUTOSTART_DIR     $(AUTOSTART_DIR)"
