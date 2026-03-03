APP_NAME      = mlController
BUNDLE_ID     = com.boinx.mlcontroller
# Xcode-integrated SPM builds to .build/apple/Products/Release/
BUILD_DIR     = .build/apple/Products/Release
APP_BUNDLE    = $(APP_NAME).app
CONTENTS      = $(APP_BUNDLE)/Contents
MACOS_DIR     = $(CONTENTS)/MacOS
RESOURCES_DIR = $(CONTENTS)/Resources
# SPM resource bundle name: <PackageName>_<TargetName>.bundle
RESOURCE_BUNDLE = $(APP_NAME)_$(APP_NAME).bundle

# ── Release Signing ──────────────────────────────────────────────────────────
SIGN_IDENTITY = Developer ID Application: Boinx Software International GmbH (6372P8EH2J)
NOTARY_PROFILE = mlController          # stored via: xcrun notarytool store-credentials
VERSION       := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist 2>/dev/null || echo "1.0")
DMG_NAME      = $(APP_NAME)-$(VERSION).dmg

.PHONY: build bundle install install-login-agent uninstall-login-agent clean run \
        release sign notarize dmg setup-notarization help

help:
	@echo "mlController Build System"
	@echo ""
	@echo "  Development:"
	@echo "    make build                — compile with Swift Package Manager"
	@echo "    make bundle               — assemble .app bundle (ad-hoc signed)"
	@echo "    make install              — copy .app to /Applications"
	@echo "    make run                  — build and open the app"
	@echo ""
	@echo "  Distribution:"
	@echo "    make release              — build, sign, notarize, and create DMG"
	@echo "    make sign                 — build bundle with Developer ID signing"
	@echo "    make notarize             — submit signed .app for Apple notarization"
	@echo "    make dmg                  — create distributable .dmg"
	@echo "    make setup-notarization   — store Apple ID credentials in keychain"
	@echo ""
	@echo "  System:"
	@echo "    make install-login-agent  — install LaunchAgent (runs at login)"
	@echo "    make uninstall-login-agent— remove LaunchAgent"
	@echo "    make clean                — remove build artifacts"

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

	@# Info.plist — expand Xcode build variable references
	sed -e 's/\$$(DEVELOPMENT_LANGUAGE)/en/g' \
	    -e 's/\$$(EXECUTABLE_NAME)/$(APP_NAME)/g' \
	    -e 's/\$$(PRODUCT_BUNDLE_IDENTIFIER)/$(BUNDLE_ID)/g' \
	    -e 's/\$$(PRODUCT_NAME)/$(APP_NAME)/g' \
	    Info.plist > $(CONTENTS)/Info.plist

	@# App icon
	cp Sources/mlController/Resources/AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns

	@# Web assets — copy directly to main Resources so Bundle.main can find them
	cp -r Sources/mlController/Resources/web $(RESOURCES_DIR)/web

	@# Ad-hoc code sign with Hardened Runtime (--options runtime required for notarization)
	codesign --force --deep --sign - --options runtime --entitlements mlController.entitlements $(APP_BUNDLE)
	@echo "==> Bundle created: $(APP_BUNDLE)"

# ── Step 3: Install to /Applications ─────────────────────────────────────────

install: bundle
	@echo "==> Installing to /Applications/$(APP_BUNDLE)..."
	@rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/$(APP_BUNDLE)
	@echo "==> Installed."

# ══════════════════════════════════════════════════════════════════════════════
#  Distribution: sign → notarize → dmg
# ══════════════════════════════════════════════════════════════════════════════

# ── Full Release Pipeline ─────────────────────────────────────────────────────

release: sign notarize dmg
	@echo ""
	@echo "════════════════════════════════════════════════════"
	@echo "  ✅  $(DMG_NAME) is ready for distribution!"
	@echo "════════════════════════════════════════════════════"

# ── Developer ID Signing ─────────────────────────────────────────────────────

sign: build
	@echo "==> Assembling $(APP_BUNDLE) (Developer ID signed)..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)

	@# Binary
	cp $(BUILD_DIR)/$(APP_NAME) $(MACOS_DIR)/$(APP_NAME)

	@# Info.plist
	sed -e 's/\$$(DEVELOPMENT_LANGUAGE)/en/g' \
	    -e 's/\$$(EXECUTABLE_NAME)/$(APP_NAME)/g' \
	    -e 's/\$$(PRODUCT_BUNDLE_IDENTIFIER)/$(BUNDLE_ID)/g' \
	    -e 's/\$$(PRODUCT_NAME)/$(APP_NAME)/g' \
	    Info.plist > $(CONTENTS)/Info.plist

	@# App icon
	cp Sources/mlController/Resources/AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns

	@# Web assets
	cp -r Sources/mlController/Resources/web $(RESOURCES_DIR)/web

	@# Developer ID code sign with Hardened Runtime
	codesign --force --deep \
	         --sign "$(SIGN_IDENTITY)" \
	         --options runtime \
	         --entitlements mlController.entitlements \
	         --timestamp \
	         $(APP_BUNDLE)

	@echo "==> Verifying signature..."
	codesign --verify --deep --strict --verbose=2 $(APP_BUNDLE)
	@echo "==> Signed bundle created: $(APP_BUNDLE)"

# ── Notarization ─────────────────────────────────────────────────────────────

notarize:
	@echo "==> Creating ZIP for notarization..."
	@rm -f $(APP_NAME).zip
	ditto -c -k --keepParent $(APP_BUNDLE) $(APP_NAME).zip

	@echo "==> Submitting to Apple notarization service..."
	xcrun notarytool submit $(APP_NAME).zip \
	      --keychain-profile "$(NOTARY_PROFILE)" \
	      --wait

	@echo "==> Stapling notarization ticket..."
	xcrun stapler staple $(APP_BUNDLE)

	@echo "==> Verifying notarization..."
	spctl --assess --type exec --verbose=2 $(APP_BUNDLE)

	@rm -f $(APP_NAME).zip
	@echo "==> Notarization complete."

# ── DMG Creation ─────────────────────────────────────────────────────────────

dmg:
	@echo "==> Creating $(DMG_NAME)..."
	@rm -f $(DMG_NAME)

	@# Create a temporary directory with the app and an Applications symlink
	@rm -rf dmg_staging
	@mkdir -p dmg_staging
	cp -r $(APP_BUNDLE) dmg_staging/
	ln -s /Applications dmg_staging/Applications

	hdiutil create -volname "$(APP_NAME)" \
	               -srcfolder dmg_staging \
	               -ov -format UDZO \
	               $(DMG_NAME)

	@rm -rf dmg_staging

	@# Sign the DMG itself
	codesign --force --sign "$(SIGN_IDENTITY)" --timestamp $(DMG_NAME)

	@echo "==> Created: $(DMG_NAME)"

# ── Setup: Store Notarization Credentials ────────────────────────────────────
#    Run once to store your Apple ID / app-specific password in the keychain.
#    This will prompt interactively for:
#      - Apple ID (email)
#      - App-specific password (generate at appleid.apple.com)
#      - Team ID: 6372P8EH2J

setup-notarization:
	@echo "==> Storing notarization credentials in keychain..."
	@echo "    You will need:"
	@echo "      • Apple ID (email address)"
	@echo "      • App-specific password (https://appleid.apple.com → Sign-In and Security → App-Specific Passwords)"
	@echo "      • Team ID: 6372P8EH2J"
	@echo ""
	xcrun notarytool store-credentials "$(NOTARY_PROFILE)"
	@echo "==> Credentials stored as keychain profile '$(NOTARY_PROFILE)'."

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
	@rm -rf $(APP_BUNDLE) .build $(APP_NAME).zip $(APP_NAME)-*.dmg dmg_staging
	@echo "==> Clean complete."

# ── Quick Run (debug build, open app) ─────────────────────────────────────────

run: bundle
	@echo "==> Launching $(APP_BUNDLE)..."
	open $(APP_BUNDLE)
