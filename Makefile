.PHONY: build run install uninstall clean headless-smoke

APP_NAME := Nicos Hidden Bar
BUNDLE_NAME := NicosHiddenMenuBar
EXECUTABLE := NicosHiddenMenuBar
BUILD_DIR := .build/release
APP_DIR := $(BUILD_DIR)/$(BUNDLE_NAME).app
INSTALL_DIR := /Applications
BUNDLE_ID := com.nstranquist.nicos-hidden-menubar
LAUNCH_AGENT := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist

build:
	swift build -c release
	@mkdir -p "$(APP_DIR)/Contents/MacOS"
	@mkdir -p "$(APP_DIR)/Contents/Resources"
	@cp "$(BUILD_DIR)/$(EXECUTABLE)" "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"
	@cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
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
	@mkdir -p "$(HOME)/Library/LaunchAgents"
	@sed "s|__BUNDLE_ID__|$(BUNDLE_ID)|g;s|__APP_PATH__|$(INSTALL_DIR)/$(BUNDLE_NAME).app|g;s|__EXECUTABLE__|$(EXECUTABLE)|g" \
		Resources/LaunchAgent.plist > "$(LAUNCH_AGENT)"
	@launchctl bootout gui/$$(id -u) "$(LAUNCH_AGENT)" 2>/dev/null || true
	@launchctl bootstrap gui/$$(id -u) "$(LAUNCH_AGENT)"
	@echo "  LaunchAgent installed — app will auto-start on login"

uninstall:
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@launchctl bootout gui/$$(id -u) "$(LAUNCH_AGENT)" 2>/dev/null || true
	@rm -f "$(LAUNCH_AGENT)"
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@echo "  Uninstalled $(BUNDLE_NAME) and removed LaunchAgent"

clean:
	swift package clean
	@rm -rf .build

# Headless launch-verify: boot + open preferences off-screen, assert no foreground.
headless-smoke:
	@./scripts/headless_smoke.sh
