APP_NAME      = mlController
BUNDLE_ID     = com.oliver.mlcontroller
# Xcode-integrated SPM builds to .build/apple/Products/Release/
BUILD_DIR     = .build/apple/Products/Release
APP_BUNDLE    = $(APP_NAME).app
CONTENTS      = $(APP_BUNDLE)/Contents
MACOS_DIR     = $(CONTENTS)/MacOS
RESOURCES_DIR = $(CONTENTS)/Resources
# SPM resource bundle name: <PackageName>_<TargetName>.bundle
RESOURCE_BUNDLE = $(APP_NAME)_$(APP_NAME).bundle

.PHONY: build bundle install install-login-agent uninstall-login-agent clean run help

help:
	@echo "mlController Build System"
	@echo ""
	@echo "  make build                — compile with Swift Package Manager"
	@echo "  make bundle               — assemble .app bundle"
	@echo "  make install              — copy .app to /Applications"
	@echo "  make install-login-agent  — install LaunchAgent (runs at login)"
	@echo "  make uninstall-login-agent— remove LaunchAgent"
	@echo "  make clean                — remove build artifacts"
	@echo "  make run                  — build and open the app"

# ── Step 1: Build ─────────────────────────────────────────────────────────────

build:
	@echo "==> Building $(APP_NAME)..."
	swift build -c release --arch arm64 --arch x86_64

# ── Step 2: Assemble .app Bundle ──────────────────────────────────────────────

bundle: build
	@echo "==> Assembling $(APP_BUNDLE)..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)

	@# Binary
	cp $(BUILD_DIR)/$(APP_NAME) $(MACOS_DIR)/$(APP_NAME)

	@# Info.plist
	cp Info.plist $(CONTENTS)/Info.plist

	@# SPM resource bundle (contains web/ assets and other resources)
	@if [ -d "$(BUILD_DIR)/$(RESOURCE_BUNDLE)" ]; then \
		cp -r $(BUILD_DIR)/$(RESOURCE_BUNDLE) $(RESOURCES_DIR)/$(RESOURCE_BUNDLE); \
	else \
		echo "Warning: Resource bundle not found at $(BUILD_DIR)/$(RESOURCE_BUNDLE)"; \
	fi

	@# Ad-hoc code sign (required to run on macOS 13+)
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "==> Bundle created: $(APP_BUNDLE)"

# ── Step 3: Install to /Applications ─────────────────────────────────────────

install: bundle
	@echo "==> Installing to /Applications/$(APP_BUNDLE)..."
	@rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/$(APP_BUNDLE)
	@echo "==> Installed."

# ── Login Item (LaunchAgent) ──────────────────────────────────────────────────

install-login-agent: install
	@echo "==> Installing LaunchAgent..."
	@mkdir -p ~/Library/LaunchAgents
	@# Unload if already loaded (ignore errors)
	@launchctl unload -w ~/Library/LaunchAgents/$(BUNDLE_ID).plist 2>/dev/null || true
	cp LaunchAgents/$(BUNDLE_ID).plist ~/Library/LaunchAgents/$(BUNDLE_ID).plist
	launchctl load -w ~/Library/LaunchAgents/$(BUNDLE_ID).plist
	@echo "==> LaunchAgent installed. mlController will launch at login."

uninstall-login-agent:
	@echo "==> Removing LaunchAgent..."
	@launchctl unload -w ~/Library/LaunchAgents/$(BUNDLE_ID).plist 2>/dev/null || true
	@rm -f ~/Library/LaunchAgents/$(BUNDLE_ID).plist
	@echo "==> LaunchAgent removed."

# ── Clean ─────────────────────────────────────────────────────────────────────

clean:
	@echo "==> Cleaning..."
	@swift package clean
	@rm -rf $(APP_BUNDLE) .build
	@echo "==> Clean complete."

# ── Quick Run (debug build, open app) ─────────────────────────────────────────

run: bundle
	@echo "==> Launching $(APP_BUNDLE)..."
	open $(APP_BUNDLE)
