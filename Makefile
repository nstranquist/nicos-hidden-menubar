.PHONY: build run install uninstall clean headless-smoke

APP_NAME := Nicos Hidden Bar
BUNDLE_NAME := NicosHiddenMenuBar
EXECUTABLE := NicosHiddenMenuBar
BUILD_DIR := .build/release
APP_DIR := $(BUILD_DIR)/$(BUNDLE_NAME).app
INSTALL_DIR := /Applications
BUNDLE_ID := com.nstranquist.nicos-hidden-menubar
LEGACY_LAUNCH_AGENT := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist

build:
	swift build -c release
	@mkdir -p "$(APP_DIR)/Contents/MacOS"
	@mkdir -p "$(APP_DIR)/Contents/Resources"
	@cp "$(BUILD_DIR)/$(EXECUTABLE)" "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"
	@cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	@codesign --force --deep --sign - "$(APP_DIR)"
	@echo "  Built: $(APP_DIR)"

run: build
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@sleep 0.3
	@open "$(APP_DIR)"

install: build
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@sleep 0.5
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@cp -R "$(APP_DIR)" "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@echo "  Installed to $(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@launchctl bootout gui/$$(id -u) "$(LEGACY_LAUNCH_AGENT)" 2>/dev/null || true
	@rm -f "$(LEGACY_LAUNCH_AGENT)"
	@open "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@echo "  Opened app — launch at login is managed from Settings"

uninstall:
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@launchctl bootout gui/$$(id -u) "$(LEGACY_LAUNCH_AGENT)" 2>/dev/null || true
	@rm -f "$(LEGACY_LAUNCH_AGENT)"
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@echo "  Uninstalled $(BUNDLE_NAME)"

clean:
	swift package clean
	@rm -rf .build

# Headless launch-verify: boot + open preferences off-screen, assert no foreground.
headless-smoke:
	@./scripts/headless_smoke.sh
