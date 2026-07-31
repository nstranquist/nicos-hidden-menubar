.PHONY: build run install install-stable uninstall clean docs-check headless-smoke \
	verify-publication publish-ready perf-check format-check release-artifact \
	scripts-check notarize print-identity reset-ax retire-legacy verify-installed

APP_NAME := Nicos Hidden Bar
BUNDLE_NAME := NicosHiddenMenuBar
EXECUTABLE := NicosHiddenMenuBar
BUILD_DIR := .build/release
APP_DIR := $(BUILD_DIR)/$(BUNDLE_NAME).app
INSTALL_DIR := /Applications
BUNDLE_ID := com.nstranquist.nicos-hidden-menubar
LEGACY_LAUNCH_AGENT := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist
LEGACY_APP_BUNDLE_ID := com.nstranquist.nicos-menubar
LEGACY_APP_LAUNCH_AGENT := $(HOME)/Library/LaunchAgents/$(LEGACY_APP_BUNDLE_ID).plist
LEGACY_APP_PROCESS := /Applications/NicosDev.app/Contents/MacOS/NicosMenuBar
LEGACY_ARCHIVE_DIR := $(HOME)/.config/nicos-hidden-menubar/legacy-launch-agents
CONFIG_PATH := $(HOME)/.config/nicos-hidden-menubar/config.json
PERF_DURATION ?= 5m
PERF_INTERVAL ?= 5s
PERF_SETTLE ?= 15s
PERF_REVEAL_CYCLES ?= 12
PERF_MAX_RSS_MB ?= 80
PERF_RECEIPT ?= .local/performance/PERF-001.json
PERF_ALLOW_UI_AUTOMATION ?= false
FORMAT_WARNING_BASELINE ?= 469
RELEASE_OUTPUT ?= .local/release
SWIFT_BUILD_FLAGS ?=

# Stable dogfood signing: Apple Development (or override).
# Ad-hoc only when no identity is found — that re-breaks Accessibility every install.
# Distribution: DEVELOPER_ID_IDENTITY=… make notarize
export BUNDLE_ID
export CODESIGN_IDENTITY
export DEVELOPER_ID_IDENTITY

retire-legacy:
	@launchctl bootout gui/$$(id -u) "$(LEGACY_APP_LAUNCH_AGENT)" 2>/dev/null || true
	@if [ -f "$(LEGACY_APP_LAUNCH_AGENT)" ]; then \
		mkdir -p "$(LEGACY_ARCHIVE_DIR)"; \
		archive="$(LEGACY_ARCHIVE_DIR)/$(LEGACY_APP_BUNDLE_ID).$$(date -u +%Y%m%dT%H%M%SZ).plist.disabled"; \
		mv "$(LEGACY_APP_LAUNCH_AGENT)" "$$archive"; \
		echo "  Archived legacy launch agent: $$archive"; \
	fi
	@pkill -f -- "$(LEGACY_APP_PROCESS)" 2>/dev/null || true

build:
	swift build -c release $(SWIFT_BUILD_FLAGS)
	@mkdir -p "$(APP_DIR)/Contents/MacOS"
	@mkdir -p "$(APP_DIR)/Contents/Resources"
	@cp "$(BUILD_DIR)/$(EXECUTABLE)" "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE)"
	@cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	@./scripts/codesign_app.sh "$(APP_DIR)"
	@echo "  Built: $(APP_DIR)"

verify-installed:
	@test -d "$(APP_DIR)" || { echo "error: release app is missing: $(APP_DIR)" >&2; exit 1; }
	@test -d "$(INSTALL_DIR)/$(BUNDLE_NAME).app" || { echo "error: installed app is missing: $(INSTALL_DIR)/$(BUNDLE_NAME).app" >&2; exit 1; }
	@codesign --verify --deep --strict "$(APP_DIR)" >/dev/null
	@codesign --verify --deep --strict "$(INSTALL_DIR)/$(BUNDLE_NAME).app" >/dev/null
	@built_hash=$$(codesign -dv --verbose=4 "$(APP_DIR)" 2>&1 | sed -n 's/^CDHash=//p'); \
	installed_hash=$$(codesign -dv --verbose=4 "$(INSTALL_DIR)/$(BUNDLE_NAME).app" 2>&1 | sed -n 's/^CDHash=//p'); \
	if [ -z "$$built_hash" ] || [ "$$built_hash" != "$$installed_hash" ]; then \
		echo "error: installed code hash does not match the release build" >&2; \
		echo "  built=$$built_hash installed=$$installed_hash" >&2; \
		exit 1; \
	fi; \
	echo "  Installed CDHash matches release build: $$installed_hash"

print-identity:
	@echo "CODESIGN_IDENTITY=$${CODESIGN_IDENTITY:-(auto)}"
	@echo "DEVELOPER_ID_IDENTITY=$${DEVELOPER_ID_IDENTITY:-(auto)}"
	@security find-identity -v -p codesigning 2>/dev/null | head -20 || true
	@echo "Auto-pick (dogfood):"
	@security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/  \1/p' | head -1 || true

run: build
	@$(MAKE) retire-legacy
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@sleep 0.3
	@open "$(APP_DIR)"

install: build
	@$(MAKE) retire-legacy
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@sleep 0.5
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@cp -R "$(APP_DIR)" "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@# Re-sign after copy (copy can invalidate ad-hoc seal; stable certs re-stamp cleanly).
	@./scripts/codesign_app.sh "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@$(MAKE) verify-installed
	@echo "  Installed to $(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@launchctl bootout gui/$$(id -u) "$(LEGACY_LAUNCH_AGENT)" 2>/dev/null || true
	@rm -f "$(LEGACY_LAUNCH_AGENT)"
	@MODE=$$(cat "$(INSTALL_DIR)/$(BUNDLE_NAME).app.codesign-mode" 2>/dev/null || echo ADHOC); \
	if [ "$$MODE" = "ADHOC" ]; then \
	  echo "  ⚠ ad-hoc sign — Accessibility will need re-grant after every install."; \
	else \
	  echo "  ✓ stable sign ($$MODE) — grant Accessibility once for this identity."; \
	fi
	@open "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@echo "  Opened app — launch at login is managed from Settings"

# First-time (or post-ad-hoc) path: reset stale Accessibility row, install with
# stable identity, open Privacy → Accessibility for a single clean grant.
install-stable: build
	@echo "  Resetting Accessibility TCC for $(BUNDLE_ID)…"
	@tccutil reset Accessibility "$(BUNDLE_ID)" 2>/dev/null || true
	@$(MAKE) retire-legacy
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@sleep 0.5
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@cp -R "$(APP_DIR)" "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@./scripts/codesign_app.sh "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@$(MAKE) verify-installed
	@launchctl bootout gui/$$(id -u) "$(LEGACY_LAUNCH_AGENT)" 2>/dev/null || true
	@rm -f "$(LEGACY_LAUNCH_AGENT)"
	@open "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@sleep 0.4
	@open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility" 2>/dev/null || true
	@echo ""
	@echo "  === One-time Accessibility grant ==="
	@echo "  1. Enable Nicos Hidden Bar under Privacy → Accessibility"
	@echo "  2. Click the chevron — it should stay white across rebuilds"
	@echo "  3. Later installs: make install (no reset) with the same Development cert"
	@echo ""

reset-ax:
	@tccutil reset Accessibility "$(BUNDLE_ID)"
	@echo "  Cleared Accessibility for $(BUNDLE_ID). Relaunch and re-enable."

uninstall:
	@LOGIN_STATE="missing"; \
	if [ -f "$(CONFIG_PATH)" ]; then \
	  LOGIN_STATE=$$(plutil -extract launchAtLogin raw -o - "$(CONFIG_PATH)" 2>/dev/null) || LOGIN_STATE="unreadable"; \
	fi; \
	if [ "$$LOGIN_STATE" = "true" ] || [ "$$LOGIN_STATE" = "unreadable" ]; then \
	  echo "error: disable Launch at login in Settings before uninstalling."; \
	  echo "  The app must unregister its Service Management login item while installed (state=$$LOGIN_STATE)."; \
		exit 1; \
	fi
	@$(MAKE) retire-legacy
	@pkill -x "$(EXECUTABLE)" 2>/dev/null || true
	@launchctl bootout gui/$$(id -u) "$(LEGACY_LAUNCH_AGENT)" 2>/dev/null || true
	@rm -f "$(LEGACY_LAUNCH_AGENT)"
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME).app"
	@rm -f "$(INSTALL_DIR)/$(BUNDLE_NAME).app.codesign-mode"
	@echo "  Uninstalled $(BUNDLE_NAME)"

clean:
	swift package clean
	@rm -rf .build

docs-check:
	@go run ./scripts/spec_evidence.go \
		-repo-root . \
		-requirements docs/initiatives/v0.2-production-hardening/requirements.yaml

format-check:
	@go run ./scripts/format_ratchet.go \
		-max-warnings "$(FORMAT_WARNING_BASELINE)" \
		Sources Tests

scripts-check:
	go test ./scripts/perf_gate.go ./scripts/perf_gate_test.go

# Headless launch-verify: boot + open preferences off-screen, assert no foreground.
headless-smoke:
	@./scripts/headless_smoke.sh

verify-publication:
	swift test
	$(MAKE) scripts-check
	$(MAKE) format-check
	$(MAKE) docs-check
	$(MAKE) build SWIFT_BUILD_FLAGS="-Xswiftc -warnings-as-errors"
	gitleaks git --no-banner --redact .
	gitleaks dir --no-banner --redact .

# Local publication gate alias (no remote push).
publish-ready: verify-publication

# Local, versioned artifact + checksum/provenance receipt. This records whether
# Developer ID and notarization evidence are present; it never claims them.
release-artifact: verify-publication
	@go run ./scripts/release_package.go \
		-app "$(APP_DIR)" \
		-out "$(RELEASE_OUTPUT)"

perf-check:
	@if [ "$(PERF_ALLOW_UI_AUTOMATION)" != "true" ]; then \
	  echo "error: perf-check visibly opens and closes the panel."; \
	  echo "  Notify the active user, then rerun with PERF_ALLOW_UI_AUTOMATION=true."; \
	  exit 1; \
	fi
	$(MAKE) install
	@mkdir -p "$$(dirname "$(PERF_RECEIPT)")"
	go run ./scripts/perf_gate.go \
		-allow-ui-automation="$(PERF_ALLOW_UI_AUTOMATION)" \
		-duration "$(PERF_DURATION)" \
		-interval "$(PERF_INTERVAL)" \
		-settle "$(PERF_SETTLE)" \
		-reveal-cycles "$(PERF_REVEAL_CYCLES)" \
		-max-rss-mb "$(PERF_MAX_RSS_MB)" \
		-out "$(PERF_RECEIPT)"

# Distribution: Developer ID + notarytool + staple (optional; needs credentials).
notarize: build
	@DEVELOPER_ID_IDENTITY="$${DEVELOPER_ID_IDENTITY}" ./scripts/notarize_app.sh "$(APP_DIR)"
